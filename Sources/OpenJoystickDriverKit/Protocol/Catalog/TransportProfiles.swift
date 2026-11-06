import Foundation

/// Per-device transport configuration resolved from controller records.
public struct DeviceTransportProfile: Equatable, Sendable {
  /// The IN endpoint addresses a record may name.
  public static let inputEndpointRange = 128...255
  /// The OUT endpoint addresses a record may name.
  public static let outputEndpointRange = 1...127
  /// The number of nanoseconds in one millisecond.
  public static let nanosecondsPerMillisecond: UInt64 = 1_000_000

  /// The IN endpoint address.
  public let inputEndpoint: UInt8
  /// The OUT endpoint address.
  public let outputEndpoint: UInt8
  /// The interface number to claim.
  public let interfaceNumber: UInt8
  /// The alternate setting to select.
  public let alternateSetting: UInt8
  /// Whether the record names the interface instead of taking the family's.
  public let hasInterfaceOverride: Bool
  /// Whether the record names the endpoints instead of taking the family's.
  public let hasEndpointOverride: Bool
  /// When true, pipeline calls setConfiguration(1) before claiming interface.
  ///
  /// Required for controllers that enumerate unconfigured (e.g. Vader 5S).
  public let needsSetConfiguration: Bool
  /// Delay after protocol handshake and before the first IN read.
  public let postHandshakeSettleNanoseconds: UInt64

  /// Creates a profile; the interface, alternate setting, overrides and settle delay default to the
  /// family's values.
  public init(
    inputEndpoint: UInt8,
    outputEndpoint: UInt8,
    interfaceNumber: UInt8 = 0,
    alternateSetting: UInt8 = 0,
    hasInterfaceOverride: Bool = false,
    hasEndpointOverride: Bool = false,
    needsSetConfiguration: Bool,
    postHandshakeSettleNanoseconds: UInt64 = 0
  ) {
    self.inputEndpoint = inputEndpoint
    self.outputEndpoint = outputEndpoint
    self.interfaceNumber = interfaceNumber
    self.alternateSetting = alternateSetting
    self.hasInterfaceOverride = hasInterfaceOverride
    self.hasEndpointOverride = hasEndpointOverride
    self.needsSetConfiguration = needsSetConfiguration
    self.postHandshakeSettleNanoseconds = postHandshakeSettleNanoseconds
  }

  /// The settle wait for a session's `settleMilliseconds`; zero when the session names none.
  static func settleNanoseconds(milliseconds: Int?) -> UInt64 {
    UInt64(milliseconds ?? 0) * nanosecondsPerMillisecond
  }

  /// This profile with the settle wait of a session's `settleMilliseconds`.
  func settling(milliseconds: Int?) -> Self {
    Self(
      inputEndpoint: inputEndpoint,
      outputEndpoint: outputEndpoint,
      interfaceNumber: interfaceNumber,
      alternateSetting: alternateSetting,
      hasInterfaceOverride: hasInterfaceOverride,
      hasEndpointOverride: hasEndpointOverride,
      needsSetConfiguration: needsSetConfiguration,
      postHandshakeSettleNanoseconds: Self.settleNanoseconds(milliseconds: milliseconds)
    )
  }

  /// The `XboxGIP` family's default endpoints, from its protocol description.
  public static let gipDefault = Self(
    inputEndpoint: UInt8(PhysicalProtocolID.xboxGIP.protocolDescription.endpoints.input),
    outputEndpoint: UInt8(PhysicalProtocolID.xboxGIP.protocolDescription.endpoints.output),
    needsSetConfiguration: false
  )
}

/// A resolved protocol binding: a family and, exactly when the family has variants, the variant
/// in use, written `family[:variant]` (for example `XboxXUSB:Receiver`, `XboxGIP:USB` or
/// `VendorFlydigi`).
public struct ProtocolBindingID: Hashable, Sendable, RawRepresentable, Codable,
  CustomStringConvertible
{
  /// The protocol family.
  public let protocolID: PhysicalProtocolID
  /// The variant of the family; nil when the family has none.
  public let variant: PhysicalProtocolVariantID?

  /// Creates a binding; the variant must be one of the family's variants, or nil for a family
  /// without variants.
  public init(_ protocolID: PhysicalProtocolID, variant: PhysicalProtocolVariantID? = nil) {
    precondition(
      Self.isValid(protocolID, variant),
      "invalid binding \(protocolID) \(variant as Any)"
    )
    self.protocolID = protocolID
    self.variant = variant
  }

  /// Whether `variant` is one the family has, or nil for a family that has none.
  private static func isValid(
    _ protocolID: PhysicalProtocolID,
    _ variant: PhysicalProtocolVariantID?
  ) -> Bool {
    guard let variant else { return protocolID.variants.isEmpty }
    return protocolID.variants.contains(variant)
  }

  /// Nil unless the text names a family and, optionally, one of its implemented variants.
  public init?(rawValue: String) {
    let parts = rawValue.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count <= 2, let protocolID = PhysicalProtocolID(rawValue: String(parts[0])) else {
      return nil
    }
    let variant = parts.count == 2 ? PhysicalProtocolVariantID(rawValue: String(parts[1])) : nil
    guard parts.count == 1 || variant != nil, Self.isValid(protocolID, variant) else { return nil }
    self.init(protocolID, variant: variant)
  }

  /// The binding as `family` or `family:variant`.
  public var rawValue: String {
    variant.map { "\(protocolID.rawValue):\($0.rawValue)" } ?? protocolID.rawValue
  }

  /// The raw value of the binding.
  public var description: String { rawValue }

  /// The binding's token in `ojd` output and in the Parser fact of the Controllers detail: the
  /// family's token, then `:` and the variant's kebab-case spelling, as in `xbox-xusb:receiver`.
  ///
  /// Each side is spelled on its own, so the variant starts a word of its own after the `:`.
  public var commandLineName: String {
    let family = protocolID.commandLineName
    return variant.map { "\(family):\(CommandLineName.kebab($0.rawValue))" } ?? family
  }

  /// Whether this binding is reached through raw USB rather than IOHID.
  public var usesRawUSB: Bool { protocolID.usesRawUSB(storedVariant: variant) }
}

/// A driver-owned policy that assembles one logical controller from several protocol roles of one
/// physical device.
///
/// A catalog row names it in `protocol.assembly`.
///
/// The vocabulary is empty, so validation rejects every name: no catalog row has
/// multi-interface evidence yet, and a selection is stored only with a live producer and
/// consumer. Discovery consumes it through ``ProtocolDriverRegistry/assemblyPolicy(for:)``;
/// until a row adds the first policy, one role is one logical controller.
public enum ControllerAssemblyPolicy: CaseIterable, Hashable, Sendable {
  /// The catalog spelling of this policy.
  public var name: String { switch self {} }

  /// The policy spelled `name`, or nil for a name outside the vocabulary.
  ///
  /// The vocabulary is empty, so every name is rejected; the first case adds the lookup over
  /// `allCases`.
  init?(name _: String) { return nil }
}

/// Whether the GIP parser sends periodic host-side keep-alive packets.
public enum GIPKeepAlivePolicy: String, Codable, Sendable {
  /// The GIP keep-alive runs.
  case enabled
  /// The GIP keep-alive does not run.
  case disabled
}

/// Who serves a HID controller that macOS also supports as a native gamepad.
public enum ControllerServer: String, Codable, Sendable {
  /// macOS serves it; OJD publishes no virtual controller and sends only the output macOS
  /// leaves undone. A controller macOS does not support is OJD's either way.
  case system = "System"
  /// OJD seizes it and publishes its own virtual controller.
  case ojd = "OJD"
}

/// How the record asks OJD to reach the controller; a record without one leaves the route to
/// the family.
public enum ControllerRecordRoute: String, Sendable {
  /// OJD's USB extension claims the controller; the extension matches only the IDs Apple granted.
  case extensionOwned = "ExtensionOwned"
}

/// A record's `tuning` section; each nil field keeps the driver's default.
public struct ControllerTuning: Codable, Equatable, Sendable {
  /// Radial stick deadzone of the output dispatcher, in 0<..<1 of full deflection.
  public let stickDeadzone: Float?
  /// Input silence after which a DualShock 4 session counts as stale.
  public let inputLivenessTimeoutMilliseconds: Int?
  /// Gap between the HID startup writes.
  public let hidStartupIntervalMilliseconds: Int?
  /// Minimum gap between HID output reports.
  public let minimumHIDOutputIntervalMilliseconds: Int?
  /// Gap between the Switch 1 startup recovery rounds.
  public let hidStartupRecoveryIntervalMilliseconds: Int?
  /// Switch 1 startup recovery rounds before the session expires.
  public let hidStartupRecoveryRounds: Int?
  /// Keep-alive ticks between Steam Triton lizard-mode resends.
  public let lizardResendTicks: Int?
  /// Timeout of one USB command transfer.
  public let usbCommandTimeoutMilliseconds: Int?
  /// Input reports between resends of the request that makes a controller announce itself.
  public let presenceResendReports: Int?
  /// Silence from an adapter or dongle after which its controller counts as disconnected.
  public let adapterDisconnectDelayMilliseconds: Int?
  /// Gap between the raw-USB startup writes.
  public let usbStartupIntervalMilliseconds: Int?
  /// Wait before the first raw-USB startup retry; each later retry waits twice as long.
  public let usbStartupRetryDelayMilliseconds: Int?
  /// Timeout of one USB transfer to a GIP controller, for rumble and startup writes.
  public let usbTransferTimeoutMilliseconds: Int?
  /// Frames that may wait behind a send to the virtual device; a full queue drops its oldest
  /// frame in favor of the newest.
  public let frameQueueCapacity: Int?

  /// The tuning that sets no key.
  public static let none = Self()

  /// The frame-queue capacity when no record, patch or family description sets one: the
  /// `default` of `tuning.frameQueueCapacity` in `controller.schema.json`.
  public static let defaultFrameQueueCapacity = 64
  /// The frame-queue capacities a record, patch or description may set: the schema's `minimum`
  /// and `maximum`.
  public static let frameQueueCapacityRange = 1...1024

  /// Creates a tuning; every key not given keeps the driver's default.
  public init(
    stickDeadzone: Float? = nil,
    inputLivenessTimeoutMilliseconds: Int? = nil,
    hidStartupIntervalMilliseconds: Int? = nil,
    minimumHIDOutputIntervalMilliseconds: Int? = nil,
    hidStartupRecoveryIntervalMilliseconds: Int? = nil,
    hidStartupRecoveryRounds: Int? = nil,
    lizardResendTicks: Int? = nil,
    usbCommandTimeoutMilliseconds: Int? = nil,
    presenceResendReports: Int? = nil,
    adapterDisconnectDelayMilliseconds: Int? = nil,
    usbStartupIntervalMilliseconds: Int? = nil,
    usbStartupRetryDelayMilliseconds: Int? = nil,
    usbTransferTimeoutMilliseconds: Int? = nil,
    frameQueueCapacity: Int? = nil
  ) {
    self.stickDeadzone = stickDeadzone
    self.inputLivenessTimeoutMilliseconds = inputLivenessTimeoutMilliseconds
    self.hidStartupIntervalMilliseconds = hidStartupIntervalMilliseconds
    self.minimumHIDOutputIntervalMilliseconds = minimumHIDOutputIntervalMilliseconds
    self.hidStartupRecoveryIntervalMilliseconds = hidStartupRecoveryIntervalMilliseconds
    self.hidStartupRecoveryRounds = hidStartupRecoveryRounds
    self.lizardResendTicks = lizardResendTicks
    self.usbCommandTimeoutMilliseconds = usbCommandTimeoutMilliseconds
    self.presenceResendReports = presenceResendReports
    self.adapterDisconnectDelayMilliseconds = adapterDisconnectDelayMilliseconds
    self.usbStartupIntervalMilliseconds = usbStartupIntervalMilliseconds
    self.usbStartupRetryDelayMilliseconds = usbStartupRetryDelayMilliseconds
    self.usbTransferTimeoutMilliseconds = usbTransferTimeoutMilliseconds
    self.frameQueueCapacity = frameQueueCapacity
  }
}

/// Complete runtime profile for one physical controller model.
public struct DeviceRuntimeProfile: Equatable, Sendable {
  /// The catalog record's `vvvv-pppp` file stem; nil for a family profile, which has no record.
  public let recordID: String?
  /// The USB transport settings of the controller.
  public internal(set) var transportProfile: DeviceTransportProfile
  /// The protocol family the default mode runs.
  public internal(set) var physicalProtocolID: PhysicalProtocolID
  /// Nil when the family has one contract or its variant is a transport variant,
  /// which classification derives from the observed transport.
  public internal(set) var physicalProtocolVariant: PhysicalProtocolVariantID?
  /// The protocol parameters of the default mode.
  public internal(set) var parameters: ProtocolParameters
  /// The corrections to the family's declared capabilities.
  public let capabilityDelta: ControllerCapabilityDelta
  /// The virtual controller backends the record prefers, in order.
  public let preferredBackends: [VirtualControllerBackendID]
  /// The record's named GIP startup packets; empty runs the family description's.
  public internal(set) var gipStartupPackets: [String]
  /// Whether the GIP keep-alive runs.
  public internal(set) var gipKeepAlivePolicy: GIPKeepAlivePolicy
  /// The assembly policy the row names; nil runs each protocol role as its own controller.
  public internal(set) var assemblyPolicy: ControllerAssemblyPolicy?
  /// Who serves the controller when macOS also supports it.
  public let server: ControllerServer
  /// The selected mode's session: startup, keep-alive, settle, shutdown, control transfers and
  /// rumble template.
  ///
  /// A family profile runs none.
  public internal(set) var session: ControllerSession
  /// The rumble report, for a driver that encodes rumble from it.
  public var rumbleTemplate: RumbleOutputTemplate? { session.rumbleTemplate }
  /// Fixed startup reports, in order; OJD sends them only to a controller it owns.
  public var startupWrites: [RecordStartupWrite] { session.startupWrites }
  /// Raw-USB startup packets; empty runs the family description's.
  public var usbStartupWrites: [USBStartupWrite] { session.usbStartupWrites }
  /// The record's input-report layouts; set exactly for the `HIDReportLayout` family.
  public let inputLayouts: ControllerInputLayouts?
  /// The record's HID usage map; set only for a `HIDDescriptor` record that declares one.
  var hidUsageMap: HIDUsageMap?
  /// The record's timing and deadzone values; nil fields keep the driver defaults.
  public internal(set) var tuning: ControllerTuning
  /// The record's route; nil leaves it to the family.
  public var route: ControllerRecordRoute?
  /// The record's Bluetooth LE vibration characteristic UUID; set only for Switch 2 controllers.
  public var bluetoothLEVibrationCharacteristic: String?

  /// The interface numbers the selected mode drives; nil binds the one interface the device
  /// exposes.
  public internal(set) var interfaceRange: ClosedRange<UInt8>?

  /// The record's modes other than `default`, in the order their match keys are tried; empty for
  /// most records.
  ///
  /// The protocol fields above are the default mode's.
  public internal(set) var modes: [ControllerMode] = []
  /// The selected mode's ID; nil while the default mode runs.
  public internal(set) var modeID: String?

  /// Whether this row is reached through raw USB rather than IOHID.
  public var usesRawUSB: Bool {
    physicalProtocolID.usesRawUSB(storedVariant: physicalProtocolVariant)
  }

  /// The binding a raw-USB row resolves to (GIP's only variant is `usb`); nil for IOHID rows,
  /// whose transport variant comes from the observed connection.
  public var rawUSBBinding: ProtocolBindingID? {
    guard usesRawUSB else { return nil }
    return ProtocolBindingID(physicalProtocolID, variant: physicalProtocolVariant ?? .usb)
  }
}
