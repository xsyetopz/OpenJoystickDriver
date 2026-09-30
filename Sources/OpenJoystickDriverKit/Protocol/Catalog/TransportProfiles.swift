import Foundation

/// Per-device transport configuration resolved from controller records.
public struct DeviceTransportProfile: Equatable, Sendable {
  public static let inputEndpointRange = 128...255
  public static let outputEndpointRange = 1...127
  public static let nanosecondsPerMillisecond: UInt64 = 1_000_000

  public let inputEndpoint: UInt8
  public let outputEndpoint: UInt8
  public let interfaceNumber: UInt8
  public let alternateSetting: UInt8
  public let hasInterfaceOverride: Bool
  public let hasEndpointOverride: Bool
  /// When true, pipeline calls setConfiguration(1) before claiming interface.
  /// Required for controllers that enumerate unconfigured (e.g. Vader 5S).
  public let needsSetConfiguration: Bool
  /// Delay after protocol handshake and before the first IN read.
  public let postHandshakeSettleNanoseconds: UInt64

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

  public static let gipDefault = Self(
    inputEndpoint: 0x82,
    outputEndpoint: 0x02,
    needsSetConfiguration: false
  )
}

/// A resolved protocol binding: a family and, exactly when the family has variants, the variant
/// in use, written `family[:variant]` (for example `xbox.xusb:receiver`, `xbox.gip:usb` or
/// `vendor.flydigi`).
public struct ProtocolBindingID: Hashable, Sendable, RawRepresentable, Codable,
  CustomStringConvertible
{
  public let protocolID: PhysicalProtocolID
  public let variant: PhysicalProtocolVariantID?

  public init(_ protocolID: PhysicalProtocolID, variant: PhysicalProtocolVariantID? = nil) {
    precondition(
      Self.isValid(protocolID, variant),
      "invalid binding \(protocolID) \(variant as Any)"
    )
    self.protocolID = protocolID
    self.variant = variant
  }

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

  public var rawValue: String {
    variant.map { "\(protocolID.rawValue):\($0.rawValue)" } ?? protocolID.rawValue
  }

  public var description: String { rawValue }

  /// Whether this binding is reached through raw USB rather than IOHID.
  public var usesRawUSB: Bool { protocolID.usesRawUSB(storedVariant: variant) }
}

/// Catalog quirks, each declared by the one protocol driver that consumes it.
///
/// A quirk changes how the driver decodes or reaches a variant; one that decodes a fixed extra
/// button bit also declares that control. Capability corrections are ``ControllerCapabilityDelta``.
public enum ControllerQuirk: String, CaseIterable, Sendable {
  /// GIP Share sits at a fixed offset from the end of the input packet (xpad `MAP_SHARE_OFFSET`).
  case shareOffset = "share-offset"
  /// Nintendo left Joy-Con axis and button permutation.
  case joyConLeft = "joy-con-left"
  /// Nintendo right Joy-Con axis and button permutation.
  case joyConRight = "joy-con-right"
  /// Wired Switch pad with a fixed HID input report and no subcommand channel (SDL
  /// `SwitchInputOnlyController`).
  case inputOnly = "input-only"
  /// Switch pad that enumerates over USB for charging but speaks the protocol only over
  /// Bluetooth (SDL `HIDAPI_DriverSwitch_IsSupportedDevice`, Linux `hid-nintendo.c` device table).
  case bluetoothOnly = "bluetooth-only"
  /// Nintendo Switch 2 controller (SDL `SDL_hidapi_switch2.c`): input report `0x05` after an init
  /// sequence on the vendor bulk interface. A Joy-Con side quirk selects the Joy-Con 2 layout.
  case switch2 = "switch-2"
  /// Switch 2 NSO GameCube controller layout, with analog triggers and flash trigger calibration.
  case gameCube = "gamecube"
  /// GameSir enhanced HID reports the inner grips in extras-byte bits 0x40 and 0x80.
  case innerGrips = "inner-grips"
  /// GameSir enhanced HID lighting memory is organized in profile slots: the driver reads the
  /// active slot at startup, tracks it, and writes color and brightness into that slot.
  case lightingSlots = "lighting-slots"
  /// 2026 Steam Controller (SDL `SteamControllerTriton`): its own report IDs, settings feature
  /// report, and repeated rumble report.
  case triton = "triton"
  /// Steam Deck built-in controller (SDL `SteamControllerNeptune`): its own state report,
  /// settings, watchdog, and rumble report.
  case neptune = "neptune"

  /// The protocol driver that declares this quirk.
  public var protocolID: PhysicalProtocolID {
    switch self {
    case .shareOffset: .xboxGIP
    case .joyConLeft, .joyConRight, .inputOnly, .bluetoothOnly, .switch2, .gameCube:
      .nintendoSwitch1
    case .innerGrips, .lightingSlots: .vendorGameSir
    case .triton, .neptune: .valveSteamController
    }
  }
}

/// A driver-owned policy that assembles one logical controller from several protocol roles of
/// one physical device. A catalog row names it in `protocol.assembly`.
///
/// The vocabulary is empty, so validation rejects every name: no catalog row has
/// multi-interface evidence yet, and a selection is stored only with a live producer and
/// consumer. Discovery consumes it through ``ProtocolDriverRegistry/assemblyPolicy(for:)``;
/// until a row adds the first policy, one role is one logical controller.
public enum ControllerAssemblyPolicy: CaseIterable, Hashable, Sendable {
  /// The catalog spelling of this policy.
  public var name: String { switch self {} }

  /// The policy spelled `name`, or nil for a name outside the vocabulary. The vocabulary is
  /// empty, so every name is rejected; the first case adds the lookup over `allCases`.
  init?(name _: String) { return nil }
}

/// Whether the GIP parser sends periodic host-side keep-alive packets.
public enum GIPKeepAlivePolicy: String, Codable, Sendable {
  case enabled
  case disabled
}

/// Complete runtime profile for one physical controller model.
public struct DeviceRuntimeProfile: Equatable, Sendable {
  /// The catalog record's `vvvv-pppp` file stem; nil for a family profile, which has no record.
  public let recordID: String?
  public let transportProfile: DeviceTransportProfile
  public let physicalProtocolID: PhysicalProtocolID
  /// Nil when the family has one contract or its variant is a transport variant,
  /// which classification derives from the observed transport.
  public let physicalProtocolVariant: PhysicalProtocolVariantID?
  public let quirks: [ControllerQuirk]
  public let capabilityDelta: ControllerCapabilityDelta
  public let preferredBackends: [VirtualControllerBackendID]
  public let gipStartupPackets: [GIPStartupPacket]
  public let gipKeepAlivePolicy: GIPKeepAlivePolicy
  /// The assembly policy the row names; nil runs each protocol role as its own controller.
  public let assemblyPolicy: ControllerAssemblyPolicy?

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
