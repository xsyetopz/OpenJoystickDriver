import Foundation

/// Serializes every write to one USB session so each write rechecks its handle in order.
actor USBOutputWriteSerialQueue {
  private var tail: Task<Void, Never>?

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

let gipReadPacketLength = 64
let gipReadTimeoutMs: UInt32 = 100
struct USBPipelineRecoveryPolicy: Sendable {
  static let standard = Self(
    openRetryDelays: [1_000_000_000, 2_000_000_000, 4_000_000_000],
    reconnectBaseDelayNanoseconds: 250_000_000,
    reconnectMaximumDelayNanoseconds: 4_000_000_000,
    accessContentionDelayNanoseconds: 30_000_000_000
  )

  let openRetryDelays: [UInt64]
  let reconnectBaseDelayNanoseconds: UInt64
  let reconnectMaximumDelayNanoseconds: UInt64
  let accessContentionDelayNanoseconds: UInt64

  func reconnectDelayNanoseconds(after attempt: Int) -> UInt64 {
    let exponent = min(max(0, attempt), 4)
    return min(reconnectMaximumDelayNanoseconds, reconnectBaseDelayNanoseconds << exponent)
  }
}
/// Target input loop cadence in nanoseconds.
///
/// Defensive pacing prevents a transport that completes timeouts immediately from
/// creating a hot loop that can trigger launchd "inefficient" kills.
let usbIdleLoopCadenceNs: UInt64 = UInt64(gipReadTimeoutMs) * 1_000_000
let usbIOErrorReconnectThreshold = 10
let usbIOErrorBackoffBaseNs: UInt64 = 250_000_000  // 250ms
let usbIOErrorBackoffMaxNs: UInt64 = 2_000_000_000  // 2s
let usbIOErrorLogIntervalNs: UInt64 = 5_000_000_000  // 5s
private let defaultIdleMonitorIntervalNanoseconds: UInt64 = 1_000_000_000

/// Manages full lifecycle of single connected controller.
/// Each controller gets its own DevicePipeline actor - one
/// failure never affects others.
actor DevicePipeline {

  let identifier: DeviceIdentifier
  let transport: Transport
  let driver: any PhysicalProtocolDriver
  let dispatcher: any OutputDispatcher
  /// Set for a controller macOS serves natively: OJD parses and routes its input, publishes no
  /// virtual gamepad for it, and writes to it only what this allowance names.
  let nativeWrites: NativeGamepadWrites?
  let observesOnly: Bool
  /// For an observe-only pipeline, the consumer that says whether anyone uses its input.
  let observedInputDemand: (any ObservedInputDemand)?
  let usbTransportProvider: (any USBTransportProvider)?
  let transportProfile: DeviceTransportProfile
  let usbRecoveryPolicy: USBPipelineRecoveryPolicy
  let idleMonitorIntervalNanoseconds: UInt64
  /// Monotonic time source for input receipt, liveness, and keep-alive timing.
  let uptimeNanoseconds: @Sendable () -> UInt64
  var isActive = false
  /// Set by the first ``stop()``; teardown side effects run once per pipeline.
  var hasStopped = false
  var usbRunGeneration: UInt64 = 0
  var usbHandle: (any USBTransportSession)?
  /// Open ``USBCommandChannel`` of a controller bound over HID; see `sendUSBCommands`.
  var usbCommandSession: (any USBTransportSession)?
  /// The binding the driver was built for: its protocol fixes the button labels, and with the
  /// interface it fixes the link that `ControllerState.connection` reports.
  let binding: ProtocolBinding?
  let interface: PhysicalInterfaceSignature?
  let buttonLabels: ControllerButtonLabels
  /// The controller's latest observed state, including input hidden from output.
  var currentInputState = ControllerState.neutral
  /// The state last sent to the dispatcher, without connection; neutral once the dispatcher was
  /// told the controller stopped.
  var lastDispatchedState = ControllerState.neutral
  /// Hides input held across a lifted foreground gate until it changes.
  var foregroundMask: ForegroundInputMask?
  let maxPacketLogEntries = 200
  var currentPower: ControllerConnectionState.Power?
  let packetLog: PacketLogBuffer
  var idleMonitorTask: Task<Void, Never>?
  var runTask: Task<Void, Never>?
  /// Keep-alive timer of the current USB run, independent of blocking input reads.
  var usbKeepAliveTask: Task<Void, Never>?
  let usbOutputWriteQueue = USBOutputWriteSerialQueue()
  var usbOwnershipReportsInFlight = 0
  var externalOutputAllowed: Bool
  var waitingForExternalNeutral = false
  var consecutiveUSBIOErrors: Int = 0
  /// The latest USB open or handshake failed and no session has started since. The pipeline keeps
  /// retrying; the device manager reads this to give a yielded HID route back.
  var usbSessionStartFailed = false
  /// The transport error of the latest failed USB startup write, cleared when a handshake starts.
  var lastUSBStartupError: USBTransportError?
  /// Whether this pipeline already reset its USB device. It resets at most once, so a device that
  /// stays unresponsive after the reset is not reset again by the same pipeline.
  var usbDeviceResetAttempted = false
  var lastUSBIOErrorLogNs: UInt64 = 0
  var inputConnectionActive: Bool
  var sessionState: ControllerSessionState
  var acceptsOnlyTeardownOutput = false
  var lastLiveInputReportNanoseconds: UInt64?
  var inputHealthMonitoringStartedNanoseconds: UInt64?
  var lastObservedInputReportNanoseconds: UInt64?
  var awaitingNeutralAfterLivenessLoss = false
  var inputHealthRecoveryCount = 0
  var startupOutputStatus: String?
  /// Whether the native startup player indicator still waits for the first input report.
  var startupPlayerIndicatorPending: Bool
  /// The player slot a USB pipeline writes with its startup writes; nil sets none.
  let usbStartupPlayerIndicator: PhysicalPlayerIndicator?

  init(
    identifier: DeviceIdentifier,
    transport: Transport,
    driver: sending any PhysicalProtocolDriver,
    dispatcher: any OutputDispatcher,
    binding: ProtocolBinding? = nil,
    interface: PhysicalInterfaceSignature? = nil,
    nativeWrites: NativeGamepadWrites? = nil,
    usbStartupPlayerIndicator: PhysicalPlayerIndicator? = nil,
    usbTransportProvider: (any USBTransportProvider)? = nil,
    transportProfile: DeviceTransportProfile = .gipDefault,
    usbRecoveryPolicy: USBPipelineRecoveryPolicy = .standard,
    externalOutputAllowed: Bool = true,
    sessionState: ControllerSessionState = .active,
    idleTimeoutNanoseconds _: UInt64 = 30_000_000_000,
    idleMonitorIntervalNanoseconds: UInt64 = defaultIdleMonitorIntervalNanoseconds,
    uptimeNanoseconds: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
  ) {
    self.identifier = identifier
    self.transport = transport
    self.driver = driver
    self.dispatcher = dispatcher
    self.binding = binding
    self.interface = interface
    self.buttonLabels =
      binding.map { ControllerButtonLabels(protocolID: $0.protocolID) } ?? .standard
    self.nativeWrites = nativeWrites
    self.observesOnly = nativeWrites != nil
    self.usbStartupPlayerIndicator = usbStartupPlayerIndicator
    self.startupPlayerIndicatorPending = nativeWrites?.setsStartupPlayerIndicator == true
    self.observedInputDemand = nativeWrites == nil ? nil : dispatcher as? any ObservedInputDemand
    self.usbTransportProvider = usbTransportProvider
    self.transportProfile = transportProfile
    self.usbRecoveryPolicy = usbRecoveryPolicy
    self.idleMonitorIntervalNanoseconds = idleMonitorIntervalNanoseconds
    self.uptimeNanoseconds = uptimeNanoseconds
    self.externalOutputAllowed = externalOutputAllowed
    self.sessionState = sessionState
    self.inputConnectionActive = !self.driver.sessionPlan.requiresInputConnectionBeforeOutput
    self.packetLog = PacketLogBuffer(maxEntries: maxPacketLogEntries)
  }
}
