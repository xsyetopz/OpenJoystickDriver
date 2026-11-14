import Foundation

/// Serializes every write to one USB session so each write rechecks its handle in order.
actor USBOutputWriteSerialQueue {
  /// The latest queued write, which the next write waits for.
  private var tail: Task<Void, Never>?

  /// Runs `operation` after every write queued before it has finished and returns its value.
  ///
  /// - Throws: The error of `operation`.
  func perform<Value: Sendable>(
    _ operation: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    let previous = tail
    let current = Task {
      if let previous { await previous.value }
      return try await operation()
    }
    tail = Task { _ = try? await current.value }
    return try await current.value
  }
}

/// The length in bytes that one GIP interrupt read requests.
let gipReadPacketLength = 64
/// The timeout in milliseconds of one GIP interrupt read.
let gipReadTimeoutMs: UInt32 = 100
/// The waits that pace the USB open, reconnect and access-contention retries of a device pipeline.
struct USBPipelineRecoveryPolicy: Sendable {
  /// The waits that a device pipeline uses by default.
  static let standard = Self(
    openRetryDelays: [1_000_000_000, 2_000_000_000, 4_000_000_000],
    reconnectBaseDelayNanoseconds: 250_000_000,
    reconnectMaximumDelayNanoseconds: 4_000_000_000,
    accessContentionDelayNanoseconds: 30_000_000_000
  )

  /// The wait after each failed open attempt, one entry per attempt.
  let openRetryDelays: [UInt64]
  /// The reconnect wait after the first failed attempt, which doubles with each further attempt.
  let reconnectBaseDelayNanoseconds: UInt64
  /// The longest reconnect wait.
  let reconnectMaximumDelayNanoseconds: UInt64
  /// The wait before the pipeline opens the interface again after an access denial.
  let accessContentionDelayNanoseconds: UInt64
  /// The failed handshakes in a row after which the pipeline stops starting the session.
  var maximumHandshakeFailures = 5

  /// The reconnect wait after `attempt` failed tries: the base wait doubled per try, up to four
  /// doublings, and capped at the maximum.
  func reconnectDelayNanoseconds(after attempt: Int) -> UInt64 {
    let exponent = min(max(0, attempt), 4)
    return min(reconnectMaximumDelayNanoseconds, reconnectBaseDelayNanoseconds << exponent)
  }
}
/// The duration in nanoseconds that one idle pass of the USB input loop takes at least, equal to
/// one read timeout.
///
/// Pacing an idle pass keeps a transport that completes timeouts at once from spinning a hot loop
/// that launchd may kill as inefficient.
let usbIdleLoopCadenceNs: UInt64 = UInt64(gipReadTimeoutMs) * 1_000_000
/// The number of consecutive USB I/O errors after which the pipeline reconnects.
let usbIOErrorReconnectThreshold = 10
/// The backoff after the first of several consecutive USB I/O errors, which doubles with each
/// error.
let usbIOErrorBackoffBaseNs: UInt64 = 250_000_000  // 250ms
/// The longest backoff after USB I/O errors.
let usbIOErrorBackoffMaxNs: UInt64 = 2_000_000_000  // 2s
/// The shortest interval between two log lines about USB I/O errors.
let usbIOErrorLogIntervalNs: UInt64 = 5_000_000_000  // 5s
/// The interval of the idle monitor when the initializer names none.
private let defaultIdleMonitorIntervalNanoseconds: UInt64 = 1_000_000_000

/// Runs the whole life of one connected controller: its USB or HID input, startup output, liveness
/// checks and the dispatch of its input events.
///
/// Each controller has its own pipeline actor, so a failure of one never affects another.
actor DevicePipeline {

  /// The logical controller that the pipeline serves.
  let identifier: LogicalControllerID
  /// The route by which the pipeline reaches the controller.
  let transport: Transport
  /// The protocol driver that parses the input and encodes the output.
  let driver: any PhysicalProtocolDriver
  /// The driver's session plan with the bound record's tuning applied.
  let plan: DriverSessionPlan
  /// The consumer of the controller's input events.
  let dispatcher: any OutputDispatcher
  /// Set for a controller macOS serves natively: OJD parses and routes its input, publishes no
  /// virtual gamepad for it, and writes to it only what this allowance names.
  let macOSOwnedOutput: MacOSOwnedOutput?
  /// Whether the pipeline only observes the controller because macOS serves it; true exactly when
  /// ``macOSOwnedOutput`` is set.
  let observesOnly: Bool
  /// For an observe-only pipeline, the consumer that says whether anyone uses its input.
  let observedInputDemand: (any ObservedInputDemand)?
  /// The provider that opens the USB sessions of the pipeline; nil when it has none.
  let usbTransportProvider: (any USBTransportProvider)?
  /// The USB endpoints, interface number and post-handshake settle delay of the route.
  let transportProfile: DeviceTransportProfile
  /// The waits between the USB open and reconnect attempts.
  let usbRecoveryPolicy: USBPipelineRecoveryPolicy
  /// The interval of the idle monitor's liveness checks.
  let idleMonitorIntervalNanoseconds: UInt64
  /// Monotonic time source for input receipt, liveness, and keep-alive timing.
  let uptimeNanoseconds: @Sendable () -> UInt64
  /// Where this pipeline notes when each frame reaches a stage, for `ojd diagnose`.
  let frameTimings: FrameTimingRecorder
  /// Whether the pipeline runs: ``start()`` sets it and ``stop()`` clears it.
  var isActive = false
  /// Set by the first ``stop()``; teardown side effects run once per pipeline.
  var hasStopped = false
  /// Counts the USB runs; a run whose generation differs from it is stale and ends.
  var usbRunGeneration: UInt64 = 0
  /// The open USB session of the raw USB route; nil when none is open.
  var usbHandle: (any USBTransportSession)?
  /// Open ``USBCommandChannel`` of a controller bound over HID; see `sendUSBCommands`.
  var usbCommandSession: (any USBTransportSession)?
  /// The binding the driver was built for; with ``interface`` it fixes the link that
  /// `ControllerState.connection` reports.
  let binding: ProtocolBinding?
  /// The interface signature that the controller was observed on.
  let interface: PhysicalInterfaceSignature?
  /// The controller's latest observed state, including input hidden from output.
  var currentInputState = ControllerState.neutral
  /// The latest observed state as the driver reported it, before the stored calibration.
  var currentRawInputState = ControllerState.neutral
  /// The stored calibration of the controller's model, read for each report.
  let calibration: @Sendable () -> ControllerCalibration
  /// When the input state last changed, for the idle disconnect.
  var idleInput: IdleInputTracker
  /// The state last sent to the dispatcher, without connection; neutral once the dispatcher was
  /// told the controller stopped.
  var lastDispatchedState = ControllerState.neutral
  /// The newest input left undispatched because a later report already waited behind it.
  var coalescedInput: ControllerEvent?
  /// Hides input held across a lifted foreground gate until it changes.
  var foregroundMask: ForegroundInputMask?
  /// The capacity of the packet log in entries.
  let maxPacketLogEntries = 200
  /// The latest power state that the driver reported; a change posts a service status change.
  var currentPower: ControllerConnectionState.Power? {
    didSet {
      if oldValue != currentPower { NotificationCenter.postServiceStatusChanged(from: self) }
    }
  }
  /// The latest Wii Remote facts that the driver reported; a change posts a service status change.
  var currentWiiRemote: WiiRemoteStatus? {
    didSet {
      if oldValue != currentWiiRemote { NotificationCenter.postServiceStatusChanged(from: self) }
    }
  }
  /// The recent packets of the controller, captured while a reader renews the capture lease.
  let packetLog: PacketLogBuffer
  /// The task that checks input liveness at the monitor interval; nil when none runs.
  var idleMonitorTask: Task<Void, Never>?
  /// The task of the current USB run; nil when none runs.
  var runTask: Task<Void, Never>?
  /// Keep-alive timer of the current USB run, independent of blocking input reads.
  var usbKeepAliveTask: Task<Void, Never>?
  /// Orders every write to the USB session.
  let usbOutputWriteQueue = USBOutputWriteSerialQueue()
  /// The number of input ownership reports being delivered; ``stop()`` waits for the run task while
  /// one is pending.
  var usbOwnershipReportsInFlight = 0
  /// Whether the foreground gate lets the controller's input reach the output; closing it
  /// neutralizes the output.
  var externalOutputAllowed: Bool
  /// Whether input held when the foreground gate lifted stays hidden until the controller returns
  /// to neutral or changes it.
  var waitingForExternalNeutral = false
  /// The number of USB I/O errors in a row; a successful read resets it.
  var consecutiveUSBIOErrors: Int = 0
  /// The latest USB open or handshake failed and no session has started since.
  ///
  /// The pipeline keeps retrying until the handshake has failed
  /// ``USBPipelineRecoveryPolicy/maximumHandshakeFailures`` times in a row; the device manager
  /// reads this to give a yielded HID route back.
  var usbSessionStartFailed = false
  /// The transport error of the latest failed USB startup write, cleared when a handshake starts.
  var lastUSBStartupError: USBTransportError?
  /// Whether this pipeline already reset its USB device.
  ///
  /// It resets at most once, so a device that stays unresponsive after the reset is not reset again
  /// by the same pipeline.
  var usbDeviceResetAttempted = false
  /// The uptime in nanoseconds of the latest logged USB I/O error.
  var lastUSBIOErrorLogNs: UInt64 = 0
  /// Whether another client holds the USB interface open exclusively; a session that opens resets
  /// it.
  ///
  /// A change posts a service status change.
  var usbOwnedByAnotherClient = false {
    didSet {
      if oldValue != usbOwnedByAnotherClient {
        NotificationCenter.postServiceStatusChanged(from: self)
      }
    }
  }
  /// The client that holds the USB interface exclusively, when known; a session that opens resets
  /// it.
  var usbExclusiveOwner: USBExclusiveOwner? {
    didSet {
      if oldValue != usbExclusiveOwner { NotificationCenter.postServiceStatusChanged(from: self) }
    }
  }
  /// Whether the input connection of the controller is up.
  ///
  /// Losing it drops the held input, so it is never replayed.
  var inputConnectionActive: Bool {
    didSet {
      if !inputConnectionActive { coalescedInput = nil }
      if oldValue != inputConnectionActive {
        NotificationCenter.postServiceStatusChanged(from: self)
      }
    }
  }
  /// Whether the controller session is active or suspended; leaving the active state drops the held
  /// input.
  var sessionState: ControllerSessionState {
    didSet { if sessionState != .active { coalescedInput = nil } }
  }
  /// Whether only output from the teardown scope passes; ``acceptOnlyTeardownOutput()`` sets it.
  var acceptsOnlyTeardownOutput = false
  /// The uptime in nanoseconds of the latest fresh input report; nil before the session read one.
  var lastLiveInputReportNanoseconds: UInt64?
  /// The uptime in nanoseconds at which liveness monitoring of the session began, which stands in
  /// for the latest fresh report until one arrives.
  var inputHealthMonitoringStartedNanoseconds: UInt64?
  /// The uptime in nanoseconds of the latest report that carried input, fresh or not;
  /// nil until the USB session read one.
  var lastObservedInputReportNanoseconds: UInt64?
  /// Whether the output stays released after input was lost, until a fresh neutral report arrives;
  /// a change posts a service status change.
  var awaitingNeutralAfterLivenessLoss = false {
    didSet {
      if oldValue != awaitingNeutralAfterLivenessLoss {
        NotificationCenter.postServiceStatusChanged(from: self)
      }
    }
  }
  /// Counted before `awaitingNeutralAfterLivenessLoss` clears, so one recovery posts once.
  var inputHealthRecoveryCount = 0
  /// Whether the session had read live input when its input was lost.
  ///
  /// The first input of a session that never had any is its start, not a recovery.
  var livenessLossFollowedInput = false
  /// Wakes once the input reports are overdue, because no event announces that.
  var staleWatchTask: Task<Void, Never>?
  /// The result of the latest startup output, for the controller details; a change posts a service
  /// status change.
  var startupOutputStatus: String? {
    didSet {
      if oldValue != startupOutputStatus { NotificationCenter.postServiceStatusChanged(from: self) }
    }
  }
  /// Whether the startup player indicator still waits for the first input report: on a
  /// controller macOS serves, and on one whose plan has `hidPlayerIndicatorFollowsFirstInput`.
  var startupPlayerIndicatorPending: Bool
  /// The player slot the manager assigned, written with the startup writes; nil sets none.
  let startupPlayerIndicator: PhysicalPlayerIndicator?

  /// Creates the pipeline of one controller in its state before ``start()``.
  init(
    identifier: LogicalControllerID,
    transport: Transport,
    driver: sending any PhysicalProtocolDriver,
    dispatcher: any OutputDispatcher,
    binding: ProtocolBinding? = nil,
    interface: PhysicalInterfaceSignature? = nil,
    macOSOwnedOutput: MacOSOwnedOutput? = nil,
    startupPlayerIndicator: PhysicalPlayerIndicator? = nil,
    usbTransportProvider: (any USBTransportProvider)? = nil,
    transportProfile: DeviceTransportProfile = .gipDefault,
    usbRecoveryPolicy: USBPipelineRecoveryPolicy = .standard,
    externalOutputAllowed: Bool = true,
    frameTimings: FrameTimingRecorder = FrameTimingRecorder(),
    sessionState: ControllerSessionState = .active,
    idleTimeoutNanoseconds _: UInt64 = 30_000_000_000,
    idleMonitorIntervalNanoseconds: UInt64 = defaultIdleMonitorIntervalNanoseconds,
    uptimeNanoseconds: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
    calibration: (@Sendable () -> ControllerCalibration)? = nil
  ) {
    self.identifier = identifier
    self.transport = transport
    self.driver = driver
    self.dispatcher = dispatcher
    self.binding = binding
    self.interface = interface
    self.macOSOwnedOutput = macOSOwnedOutput
    self.observesOnly = macOSOwnedOutput != nil
    self.startupPlayerIndicator = startupPlayerIndicator
    self.observedInputDemand =
      macOSOwnedOutput == nil ? nil : dispatcher as? any ObservedInputDemand
    self.usbTransportProvider = usbTransportProvider
    self.transportProfile = transportProfile
    self.usbRecoveryPolicy = usbRecoveryPolicy
    self.idleMonitorIntervalNanoseconds = idleMonitorIntervalNanoseconds
    self.frameTimings = frameTimings
    self.calibration =
      calibration ?? {
        DeviceCatalog.current.withLock { $0.calibration(of: identifier.model) }
      }
    self.uptimeNanoseconds = uptimeNanoseconds
    self.idleInput = IdleInputTracker(now: uptimeNanoseconds())
    self.externalOutputAllowed = externalOutputAllowed
    self.sessionState = sessionState
    let tunedPlan = self.driver.sessionPlan.tuned(binding?.record?.tuning ?? .none)
    self.plan = tunedPlan
    self.startupPlayerIndicatorPending =
      macOSOwnedOutput?.setsStartupPlayerIndicator == true
      || (startupPlayerIndicator != nil && tunedPlan.hidPlayerIndicatorFollowsFirstInput)
    self.inputConnectionActive = !tunedPlan.requiresInputConnectionBeforeOutput
    self.packetLog = PacketLogBuffer(maxEntries: maxPacketLogEntries)
  }
}
