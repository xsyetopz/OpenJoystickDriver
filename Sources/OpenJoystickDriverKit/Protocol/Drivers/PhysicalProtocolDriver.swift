import Foundation

/// A vendor-class USB interface that carries the controller's commands beside its HID interface.
///
/// The pipeline opens it on demand while the controller runs over HID, writes each `.usb` packet
/// to ``outEndpoint``, and reads one reply from ``inEndpoint`` into
/// ``PhysicalProtocolDriver/consumeUSBCommandReply(_:)``.
public struct USBCommandChannel: Equatable, Sendable {
  public let interfaceNumber: UInt8
  public let outEndpoint: UInt8
  public let inEndpoint: UInt8
  /// Largest reply read after each command.
  public let replyLength: Int
  /// Timeout of each reply read; a command without a reply costs this much.
  public let replyTimeoutMilliseconds: UInt32

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
  public let usbStartupIntervalNanoseconds: UInt64
  /// Delays before each repeated USB startup attempt after a failed one; empty means one attempt.
  public let usbStartupRetryDelays: [UInt64]
  /// Interval between USB keep-alive writes; nil when the protocol sends none.
  public let usbKeepAliveIntervalNanoseconds: UInt64?
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
  /// Interval between HID keep-alive writes; nil when the protocol sends none.
  public let hidKeepAliveIntervalNanoseconds: UInt64?
  /// Minimum spacing between user-output HID output reports (rumble, lighting); 0 is unlimited.
  public internal(set) var minimumHIDOutputIntervalNanoseconds: UInt64
  /// True when the driver sets no player indicator itself: the manager picks a free slot per
  /// controller and the pipeline writes it with the USB startup writes, or, when output waits for
  /// an input connection, each time the logical controller connects.
  public let assignsStartupPlayerIndicator: Bool
  /// USB command interface for `.usb` writes of a controller bound over HID; nil when none.
  public let usbCommandChannel: USBCommandChannel?

  public init(
    inputReportLivenessTimeoutNanoseconds: UInt64? = nil,
    requiresInputConnectionBeforeOutput: Bool = false,
    parsesHIDElementValues: Bool = false,
    usbStartupIntervalNanoseconds: UInt64 = 0,
    usbStartupRetryDelays: [UInt64] = [],
    usbKeepAliveIntervalNanoseconds: UInt64? = nil,
    hidStartupIntervalNanoseconds: UInt64 = 0,
    outputPrecedesFeatureReads: Bool = false,
    requiresStartupOutput: Bool = false,
    validatesFeatureReplies: Bool = false,
    hasStartupRecovery: Bool = false,
    hidStartupRecoveryIntervalNanoseconds: UInt64 = 200_000_000,
    hidStartupRecoveryRounds: Int = 2,
    hidKeepAliveIntervalNanoseconds: UInt64? = nil,
    minimumHIDOutputIntervalNanoseconds: UInt64 = 0,
    assignsStartupPlayerIndicator: Bool = false,
    usbCommandChannel: USBCommandChannel? = nil
  ) {
    self.inputReportLivenessTimeoutNanoseconds = inputReportLivenessTimeoutNanoseconds
    self.requiresInputConnectionBeforeOutput = requiresInputConnectionBeforeOutput
    self.parsesHIDElementValues = parsesHIDElementValues
    self.usbStartupIntervalNanoseconds = usbStartupIntervalNanoseconds
    self.usbStartupRetryDelays = usbStartupRetryDelays
    self.usbKeepAliveIntervalNanoseconds = usbKeepAliveIntervalNanoseconds
    self.hidStartupIntervalNanoseconds = hidStartupIntervalNanoseconds
    self.outputPrecedesFeatureReads = outputPrecedesFeatureReads
    self.requiresStartupOutput = requiresStartupOutput
    self.validatesFeatureReplies = validatesFeatureReplies
    self.hasStartupRecovery = hasStartupRecovery
    self.hidStartupRecoveryIntervalNanoseconds = hidStartupRecoveryIntervalNanoseconds
    self.hidStartupRecoveryRounds = hidStartupRecoveryRounds
    self.hidKeepAliveIntervalNanoseconds = hidKeepAliveIntervalNanoseconds
    self.minimumHIDOutputIntervalNanoseconds = minimumHIDOutputIntervalNanoseconds
    self.assignsStartupPlayerIndicator = assignsStartupPlayerIndicator
    self.usbCommandChannel = usbCommandChannel
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
    return plan
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
  /// last rumble a combined report repeats). Throws `unsupportedCapability` for a command the
  /// protocol has no output for, and `notReady` while its session cannot carry the command yet.
  func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan
}

extension PhysicalProtocolDriver {
  public func parse(
    elementValue _: HIDElementValue,
    receivedAt _: MonotonicTimestamp
  ) -> ControllerEvent? { nil }
  public var latestInputReportFormat: String? { nil }
  public var power: ControllerConnectionState.Power? { nil }
  public func resetProtocolState() {}
  public func startupWrites() -> [PhysicalOutputWrite] { [] }
  public func activationWrites() -> [PhysicalOutputWrite] { [] }
  public func deactivationWrites() -> [PhysicalOutputWrite] { [] }
  public func startupFeatureReads() -> [PhysicalHIDFeatureReadRequest] { [] }
  public func consumeFeatureReply(_: Data, request _: PhysicalHIDFeatureReadRequest) -> Bool {
    false
  }
  public func consumeUSBCommandReply(_: [UInt8]) {}
  public func startupRecoveryWrites() -> [PhysicalOutputWrite] { [] }
  public func expireStartupRecovery() {}
  public func presenceRequestWrite() -> PhysicalOutputWrite? { nil }
  public func keepAliveWrites() -> [PhysicalOutputWrite] { [] }
  public func drainPendingWrites() -> [PhysicalOutputWrite] { [] }

  public func inputConnectionWrites(for _: ControllerInputConnectionState) -> [PhysicalOutputWrite]
  { [] }

  public func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    throw .unsupportedCapability(command.capability)
  }
}
