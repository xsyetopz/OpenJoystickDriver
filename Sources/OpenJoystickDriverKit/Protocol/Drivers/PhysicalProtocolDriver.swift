import Foundation

/// A vendor-class USB interface that carries the controller's commands beside its HID interface.
///
/// The pipeline opens it on demand while the controller runs over HID, writes each `.usb` packet
/// to ``outEndpoint``, and reads one reply from ``inEndpoint`` into
/// ``PhysicalProtocolDriver/consumeUSBCommandReply(_:)``.
public struct USBCommandChannel: Equatable, Sendable {
  /// The USB interface number that carries the commands.
  public let interfaceNumber: UInt8
  /// The address of the OUT endpoint that commands are written to.
  public let outEndpoint: UInt8
  /// The address of the IN endpoint that replies are read from.
  public let inEndpoint: UInt8
  /// Largest reply read after each command.
  public let replyLength: Int
  /// Timeout of each reply read; a command without a reply costs this much.
  public let replyTimeoutMilliseconds: UInt32

  /// Creates a description of the command channel.
  public init(
    interfaceNumber: UInt8,
    outEndpoint: UInt8,
    inEndpoint: UInt8,
    replyLength: Int,
    replyTimeoutMilliseconds: UInt32
  ) {
    self.interfaceNumber = interfaceNumber
    self.outEndpoint = outEndpoint
    self.inEndpoint = inEndpoint
    self.replyLength = replyLength
    self.replyTimeoutMilliseconds = replyTimeoutMilliseconds
  }
}

/// The transport a driver's keep-alive writes go over.
public enum KeepAliveChannel: Sendable {
  /// Raw-USB writes, on the USB input loop.
  case usb
  /// HID output reports.
  case hid
}

/// Session behavior a driver fixes at construction for its bound family and variant.
public struct DriverSessionPlan: Equatable, Sendable {
  /// Maximum age of the last fresh input report before held controls are retired; nil when the
  /// protocol has no report liveness contract.
  public internal(set) var inputReportLivenessTimeoutNanoseconds: UInt64?
  /// True when output must wait until a logical controller connects inside the transport.
  public let requiresInputConnectionBeforeOutput: Bool
  /// True when the driver parses IOKit-decoded element values instead of raw input reports; only
  /// such a driver has element values delivered, since decoding every report costs CPU.
  public let parsesHIDElementValues: Bool
  /// Delay between consecutive USB startup writes.
  public internal(set) var usbStartupIntervalNanoseconds: UInt64
  /// Delays before each repeated USB startup attempt after a failed one; empty means one attempt.
  public internal(set) var usbStartupRetryDelays: [UInt64]
  /// The channels the driver keeps alive; empty when the protocol sends no keep-alive.
  public internal(set) var keepAliveChannels: Set<KeepAliveChannel>
  /// Interval between keep-alive writes on every channel in ``keepAliveChannels``.
  ///
  /// The family's description holds it (`defaults.session.keepAlive.intervalMilliseconds`) and
  /// ``withKeepAlive(of:)`` fills it; nil until then and for a driver without a channel.
  public internal(set) var keepAliveIntervalNanoseconds: UInt64?
  /// Interval between USB keep-alive writes; nil when the protocol sends none over USB.
  public var usbKeepAliveIntervalNanoseconds: UInt64? {
    keepAliveChannels.contains(.usb) ? keepAliveIntervalNanoseconds : nil
  }
  /// Delay between consecutive HID startup and startup-recovery writes.
  public internal(set) var hidStartupIntervalNanoseconds: UInt64
  /// True when HID startup writes go before the startup feature reads; otherwise after them.
  public let outputPrecedesFeatureReads: Bool
  /// True when failed HID startup writes must keep virtual output gated.
  public let requiresStartupOutput: Bool
  /// True when feature-read replies reach the driver's `consumeFeatureReply(_:request:)`, and a
  /// rejected or failed read is retried.
  public let validatesFeatureReplies: Bool
  /// True when replies to startup writes are re-requested for a bounded window after startup.
  public let hasStartupRecovery: Bool
  /// Delay between startup recovery rounds.
  public internal(set) var hidStartupRecoveryIntervalNanoseconds: UInt64
  /// Startup recovery rounds after the first startup; the session expires after the last.
  public internal(set) var hidStartupRecoveryRounds: Int
  /// Interval between HID keep-alive writes; nil when the protocol sends none over HID.
  public var hidKeepAliveIntervalNanoseconds: UInt64? {
    keepAliveChannels.contains(.hid) ? keepAliveIntervalNanoseconds : nil
  }
  /// Minimum spacing between user-output HID output reports (rumble, lighting); 0 is unlimited.
  public internal(set) var minimumHIDOutputIntervalNanoseconds: UInt64
  /// True when the driver sets no player indicator itself: the manager picks a free slot per
  /// controller OJD serves, and the pipeline writes it with the startup writes, or, when output
  /// waits for an input connection, each time the logical controller connects.
  public let assignsStartupPlayerIndicator: Bool
  /// True when an HID controller ignores the player indicator written with the startup writes,
  /// so the assigned slot is written after its first input report instead.
  public let hidPlayerIndicatorFollowsFirstInput: Bool
  /// USB command interface for `.usb` writes of a controller bound over HID; nil when none.
  public let usbCommandChannel: USBCommandChannel?
  /// What the user does before the controller sends input, from the family's description for the
  /// bound variant (``withDefaults(of:variant:)``); nil when input starts on its own.
  public internal(set) var inputStartAction: InputStartAction?

  /// Creates a session plan; each parameter defaults to the value of a protocol without that
  /// concern.
  public init(
    inputReportLivenessTimeoutNanoseconds: UInt64? = nil,
    requiresInputConnectionBeforeOutput: Bool = false,
    parsesHIDElementValues: Bool = false,
    usbStartupIntervalNanoseconds: UInt64 = 0,
    usbStartupRetryDelays: [UInt64] = [],
    keepAliveChannels: Set<KeepAliveChannel> = [],
    keepAliveIntervalNanoseconds: UInt64? = nil,
    hidStartupIntervalNanoseconds: UInt64 = 0,
    outputPrecedesFeatureReads: Bool = false,
    requiresStartupOutput: Bool = false,
    validatesFeatureReplies: Bool = false,
    hasStartupRecovery: Bool = false,
    hidStartupRecoveryIntervalNanoseconds: UInt64 = 0,
    hidStartupRecoveryRounds: Int = 0,
    minimumHIDOutputIntervalNanoseconds: UInt64 = 0,
    assignsStartupPlayerIndicator: Bool = false,
    hidPlayerIndicatorFollowsFirstInput: Bool = false,
    usbCommandChannel: USBCommandChannel? = nil
  ) {
    self.inputReportLivenessTimeoutNanoseconds = inputReportLivenessTimeoutNanoseconds
    self.requiresInputConnectionBeforeOutput = requiresInputConnectionBeforeOutput
    self.parsesHIDElementValues = parsesHIDElementValues
    self.usbStartupIntervalNanoseconds = usbStartupIntervalNanoseconds
    self.usbStartupRetryDelays = usbStartupRetryDelays
    self.keepAliveChannels = keepAliveChannels
    self.keepAliveIntervalNanoseconds = keepAliveIntervalNanoseconds
    self.hidStartupIntervalNanoseconds = hidStartupIntervalNanoseconds
    self.outputPrecedesFeatureReads = outputPrecedesFeatureReads
    self.requiresStartupOutput = requiresStartupOutput
    self.validatesFeatureReplies = validatesFeatureReplies
    self.hasStartupRecovery = hasStartupRecovery
    self.hidStartupRecoveryIntervalNanoseconds = hidStartupRecoveryIntervalNanoseconds
    self.hidStartupRecoveryRounds = hidStartupRecoveryRounds
    self.minimumHIDOutputIntervalNanoseconds = minimumHIDOutputIntervalNanoseconds
    self.assignsStartupPlayerIndicator = assignsStartupPlayerIndicator
    self.hidPlayerIndicatorFollowsFirstInput = hidPlayerIndicatorFollowsFirstInput
    self.usbCommandChannel = usbCommandChannel
  }

  /// This plan with the timings and the input start action that the protocol description of
  /// `family` defaults for `variant`.
  ///
  /// The timings replace the plan's own.
  func withDefaults(
    of family: PhysicalProtocolID,
    variant: PhysicalProtocolVariantID? = nil
  ) -> Self {
    var plan = withKeepAlive(of: family)
    plan.inputStartAction = family.protocolDescription.inputStartAction(variant: variant)
    return family.protocolDescription.tuning(variant: variant).map(plan.tuned) ?? plan
  }

  /// This plan with the keep-alive interval of the description of `family`.
  ///
  /// A plan with channels needs a description that has a keep-alive; without one the interval stays
  /// nil and the plan sends no keep-alive, which the driver tests catch.
  func withKeepAlive(of family: PhysicalProtocolID) -> Self {
    withKeepAlive(of: family.protocolDescription)
  }

  /// This plan with the keep-alive interval of `description`.
  func withKeepAlive(of description: ProtocolDescription) -> Self {
    var plan = self
    if !keepAliveChannels.isEmpty {
      plan.keepAliveIntervalNanoseconds = description.keepAlive.map {
        UInt64($0.intervalMilliseconds) * DeviceTransportProfile.nanosecondsPerMillisecond
      }
    }
    return plan
  }

  /// This plan with a keep-alive at the resend interval of `template` on the channel the template
  /// writes to.
  ///
  /// The keep-alive is added when the template names an interval and the plan has no keep-alive of
  /// its own.
  func withRumbleResend(of template: RumbleOutputTemplate?) -> Self {
    guard let milliseconds = template?.resendIntervalMilliseconds,
      let target = template?.target, keepAliveChannels.isEmpty
    else { return self }
    var plan = self
    plan.keepAliveChannels = [target.hidReport == nil ? .usb : .hid]
    plan.keepAliveIntervalNanoseconds =
      UInt64(milliseconds) * DeviceTransportProfile.nanosecondsPerMillisecond
    return plan
  }

  /// This plan with the record's tuned timings in place of the driver defaults.
  func tuned(_ tuning: ControllerTuning) -> Self {
    func nanoseconds(_ milliseconds: Int) -> UInt64 {
      UInt64(milliseconds) * DeviceTransportProfile.nanosecondsPerMillisecond
    }
    var plan = self
    if let value = tuning.inputLivenessTimeoutMilliseconds {
      plan.inputReportLivenessTimeoutNanoseconds = nanoseconds(value)
    }
    if let value = tuning.hidStartupIntervalMilliseconds {
      plan.hidStartupIntervalNanoseconds = nanoseconds(value)
    }
    if let value = tuning.minimumHIDOutputIntervalMilliseconds {
      plan.minimumHIDOutputIntervalNanoseconds = nanoseconds(value)
    }
    if let value = tuning.hidStartupRecoveryIntervalMilliseconds {
      plan.hidStartupRecoveryIntervalNanoseconds = nanoseconds(value)
    }
    if let value = tuning.hidStartupRecoveryRounds { plan.hidStartupRecoveryRounds = value }
    if let value = tuning.usbStartupIntervalMilliseconds {
      plan.usbStartupIntervalNanoseconds = nanoseconds(value)
    }
    if let value = tuning.usbStartupRetryDelayMilliseconds {
      plan.usbStartupRetryDelays = plan.usbStartupRetryDelays.indices.map {
        nanoseconds(value) << UInt64($0)
      }
    }
    return plan
  }
}

extension PhysicalProtocolID {
  /// The tuning that a driver of this family and stored variant reads: the description's
  /// defaults, with the record's values over them.
  func driverTuning(
    variant: PhysicalProtocolVariantID? = nil,
    record: ControllerTuning = .none
  ) -> ControllerTuning {
    (protocolDescription.tuning(variant: variant) ?? .none).overlaid(by: record)
  }

  /// The value of `key` that a driver of this family reads: from `tuning` when the registry
  /// supplies the record's, otherwise (or where it sets none) from the description's defaults.
  ///
  /// A description that defaults none for a key its driver reads is a defect.
  func described(_ key: KeyPath<ControllerTuning, Int?>, in tuning: ControllerTuning?) -> Int {
    guard let value = driverTuning().overlaid(by: tuning ?? .none)[keyPath: key] else {
      preconditionFailure("\(descriptionFileStem).plist defaults no \(key)")
    }
    return value
  }

  /// The rumble template a driver of this family and stored variant encodes from: the record's
  /// when it sets one, otherwise the description's for the variant; nil when neither does.
  func rumbleTemplate(
    variant: PhysicalProtocolVariantID?,
    record: RumbleOutputTemplate?
  ) -> RumbleOutputTemplate? {
    record ?? protocolDescription.rumbleTemplate(variant: variant)
  }

  /// The rumble template of a family whose description always sets one for `variant`.
  ///
  /// A description that sets none is a defect.
  func describedRumbleTemplate(
    variant: PhysicalProtocolVariantID?,
    record: RumbleOutputTemplate?
  ) -> RumbleOutputTemplate {
    guard let template = rumbleTemplate(variant: variant, record: record) else {
      preconditionFailure("\(descriptionFileStem).plist sets no rumble template")
    }
    return template
  }

  /// The count `limit` that the family's description sets for its driver.
  ///
  /// A description that sets none for a count its driver reads is a defect.
  func described(limit: KeyPath<ProtocolDescription, Int?>) -> Int {
    guard let value = protocolDescription[keyPath: limit] else {
      preconditionFailure("\(descriptionFileStem).plist sets no \(limit)")
    }
    return value
  }
}

extension PhysicalProtocolID {
  /// The controls that the family's description gives every controller of it.
  ///
  /// A driver adds only what its record or layout makes true.
  var describedControls: ControllerCapabilities {
    guard let controls = protocolDescription.controls else {
      preconditionFailure("\(descriptionFileStem).plist describes no controls")
    }
    return controls
  }
}

/// Owns one bound physical protocol: input framing and parsing, presence, and session state.
///
/// ``ProtocolDriverRegistry`` builds a driver for one bound family and variant after checking
/// the claimed interface contract. Each protocol (GIP for Xbox, DS4 for PlayStation,
/// descriptor-driven HID) has its own conforming type.
///
/// Only values that are empty for a protocol without the concern have defaults; presence
/// consumption is required, because a driver that gates output on presence and misses it would
/// keep output gated forever. Output capabilities and the default colour are required for the
/// same reason: each encoder defaults to nil (unsupported), so a driver that implements one must
/// also state the capability that lets output reach it.
public protocol PhysicalProtocolDriver: AnyObject {
  /// Immutable normalized controls and sample formats this driver can emit.
  var capabilities: ControllerCapabilities { get }

  /// Liveness, presence gating, and USB and HID lifecycle timing for the pipeline session.
  var sessionPlan: DriverSessionPlan { get }

  /// Decodes one raw packet into the controller's full state after it.
  ///
  /// Called once for every USB interrupt transfer or HID input report the system receives from
  /// the controller, stamped with its host receipt time. Returns nil for a frame that carries no
  /// input (an acknowledgement, a status or presence frame, a partial transfer); such a frame may
  /// still change ``power`` or the connection state. A throw leaves the last valid state intact.
  func parse(report: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent?

  /// Folds one IOKit-decoded HID element value into the controller's full state; nil when the
  /// value maps to no control.
  func parse(elementValue: HIDElementValue, receivedAt: MonotonicTimestamp) -> ControllerEvent?

  /// Wire format of the latest input report, for input health diagnostics.
  var latestInputReportFormat: String? { get }

  /// Power state decoded from the latest report, outside the controller event stream; `nil`
  /// until the device reports it.
  var power: ControllerConnectionState.Power? { get }

  /// The Wii Remote session facts; `nil` for every other family.
  var wiiRemoteStatus: WiiRemoteStatus? { get }

  /// Returns and clears the most recent logical connection state change, if any.
  func consumeInputConnectionStateChange() -> ControllerInputConnectionState?

  /// Resets protocol state whenever a physical transport session starts or ends.
  func resetProtocolState()

  /// Writes that start a session, sent in order at ``DriverSessionPlan`` startup spacing; called
  /// again for every startup attempt.
  func startupWrites() -> [PhysicalOutputWrite]

  /// Writes that put the controller into the mode OJD consumes, sent after the startup feature
  /// reads, or once a logical controller connects when output waits for one.
  func activationWrites() -> [PhysicalOutputWrite]

  /// Writes that return the controller to its own mode when OJD stops consuming it.
  func deactivationWrites() -> [PhysicalOutputWrite]

  /// Feature reports read after startup, in order; each reply may be offered to
  /// ``consumeFeatureReply(_:request:)``.
  func startupFeatureReads() -> [PhysicalHIDFeatureReadRequest]

  /// Takes one startup feature-read reply; false rejects it and keeps the previous state.
  func consumeFeatureReply(_ data: Data, request: PhysicalHIDFeatureReadRequest) -> Bool

  /// Takes one reply read from the plan's ``DriverSessionPlan/usbCommandChannel``.
  func consumeUSBCommandReply(_ bytes: [UInt8])

  /// Writes that re-request startup replies still missing, for one recovery round.
  func startupRecoveryWrites() -> [PhysicalOutputWrite]

  /// Ends the startup recovery window; no startup reply is awaited afterwards.
  func expireStartupRecovery()

  /// A write asking the transport to report its current logical controller connection.
  func presenceRequestWrite() -> PhysicalOutputWrite?

  /// Writes for one keep-alive tick at the plan's USB or HID keep-alive interval.
  func keepAliveWrites() -> [PhysicalOutputWrite]

  /// Writes that turn the controller off, sent once by the pipeline's deliberate stop and never
  /// after an I/O error or an unplug.
  func powerOffWrites() -> [PhysicalOutputWrite]

  /// Tells the driver whether the active profile binds a pointer axis; the pipeline calls it
  /// before each report is parsed.
  func setPointerInputWanted(_ wanted: Bool)

  /// Returns and clears the writes produced while parsing input, such as acknowledgements.
  ///
  /// Parsing stays synchronous and deterministic; the pipeline performs these writes in order.
  func drainPendingWrites() -> [PhysicalOutputWrite]

  /// Writes for one logical controller connect or disconnect inside the transport.
  func inputConnectionWrites(for state: ControllerInputConnectionState) -> [PhysicalOutputWrite]

  /// Physical output this driver implements; arbitration sends only what it advertises, and each
  /// advertised capability has an `encode(_:)` case that returns a plan.
  var outputCapabilities: PhysicalControllerOutputCapabilities { get }

  /// Lightbar colour restored when no owner claims colour; nil when the protocol has none.
  var defaultColor: ControllerColor? { get }

  /// Writes that carry `command`. Encoding may advance protocol state (sequence numbers, the
  /// last rumble a combined report repeats). Throws `UnsupportedCapability` for a command the
  /// protocol has no output for, and `NotReady` while its session cannot carry the command yet.
  func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan
}

extension PhysicalProtocolDriver {
  /// Default: no element value maps to a control.
  public func parse(
    elementValue _: HIDElementValue,
    receivedAt _: MonotonicTimestamp
  ) -> ControllerEvent? { nil }
  /// Default: no input report format.
  public var latestInputReportFormat: String? { nil }
  /// Default: no power state.
  public var power: ControllerConnectionState.Power? { nil }
  /// Default: no Wii Remote facts.
  public var wiiRemoteStatus: WiiRemoteStatus? { nil }
  /// Default: the driver keeps no protocol state to reset.
  public func resetProtocolState() {}
  /// Default: no startup writes.
  public func startupWrites() -> [PhysicalOutputWrite] { [] }
  /// Default: no activation writes.
  public func activationWrites() -> [PhysicalOutputWrite] { [] }
  /// Default: no deactivation writes.
  public func deactivationWrites() -> [PhysicalOutputWrite] { [] }
  /// Default: no startup feature reads.
  public func startupFeatureReads() -> [PhysicalHIDFeatureReadRequest] { [] }
  /// Default: rejects every reply.
  public func consumeFeatureReply(_: Data, request _: PhysicalHIDFeatureReadRequest) -> Bool {
    false
  }
  /// Default: ignores the reply.
  public func consumeUSBCommandReply(_: [UInt8]) {}
  /// Default: no startup recovery writes.
  public func startupRecoveryWrites() -> [PhysicalOutputWrite] { [] }
  /// Default: no startup reply is awaited, so there is nothing to end.
  public func expireStartupRecovery() {}
  /// Default: no presence request.
  public func presenceRequestWrite() -> PhysicalOutputWrite? { nil }
  /// Default: no keep-alive writes.
  public func keepAliveWrites() -> [PhysicalOutputWrite] { [] }
  /// Default: the controller is left on.
  public func powerOffWrites() -> [PhysicalOutputWrite] { [] }
  /// Default: the driver has no pointer hardware to turn on.
  public func setPointerInputWanted(_: Bool) {}
  /// Default: no pending writes.
  public func drainPendingWrites() -> [PhysicalOutputWrite] { [] }

  /// Default: no connection writes.
  public func inputConnectionWrites(for _: ControllerInputConnectionState) -> [PhysicalOutputWrite]
  { [] }

  /// Default: throws ``ControllerOutputError/unsupportedCapability(_:)`` for every command.
  public func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    throw .unsupportedCapability(command.capability)
  }
}
