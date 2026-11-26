import Foundation

/// Physical protocol families with an implemented OJD parser.
///
/// A family joins this enum only when a driver for it exists.
public struct PhysicalProtocolID: Hashable, Sendable, RawRepresentable, CaseIterable, Codable {
  /// The family's name, UpperCamelCase.
  public let rawValue: String

  private init(builtIn name: String) { rawValue = name }

  /// A family that a description document names; it is not built in.
  init(documented name: String) { rawValue = name }

  /// The families with an implemented OJD parser, in declaration order.
  public static let allCases: [Self] = [
    .hidDescriptor, .hidReportLayout, .xboxXID, .xboxXUSB, .xboxGIP, .sonySixaxis, .sonyDualShock4,
    .sonyDualSense, .nintendoSwitch1, .nintendoSwitch2, .nintendoSwitchInputOnly,
    .valveSteamController, .valveSteamTriton, .valveSteamDeck, .vendorPS3ThirdParty, .vendorGameSir,
    .vendorNVIDIAShield, .nintendoWii, .nintendoGameCubeAdapter,
  ]

  /// The family named `rawValue`: a built-in one, or one a loaded description document names.
  public init?(rawValue: String) {
    if let builtIn = Self.allCases.first(where: { $0.rawValue == rawValue }) {
      self = builtIn
    } else if DocumentedProtocolFamilies.description(named: rawValue) != nil {
      self.init(documented: rawValue)
    } else {
      return nil
    }
  }

  /// Decodes the family's name; a name that no family has is refused.
  public init(from decoder: any Decoder) throws {
    let name = try decoder.singleValueContainer().decode(String.self)
    guard let family = Self(rawValue: name) else {
      throw DecodingError.dataCorruptedError(
        in: try decoder.singleValueContainer(),
        debugDescription: "\(name) is not a protocol family"
      )
    }
    self = family
  }

  /// Encodes the family's name.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  /// Whether a description document names this family and OJD does not build it in.
  public var isDocumented: Bool { !Self.allCases.contains(self) }

  /// Controllers recognised from their HID report descriptor alone.
  public static let hidDescriptor = Self(builtIn: "HIDDescriptor")
  /// A fixed input-report layout from the controller record (``ControllerInputLayouts``).
  public static let hidReportLayout = Self(builtIn: "HIDReportLayout")
  /// The original Xbox controller protocol (XID).
  public static let xboxXID = Self(builtIn: "XboxXID")
  /// The Xbox 360 controller protocol (XUSB).
  public static let xboxXUSB = Self(builtIn: "XboxXUSB")
  /// The Xbox One and later controller protocol (GIP).
  public static let xboxGIP = Self(builtIn: "XboxGIP")
  /// The Sony Sixaxis and DualShock 3 protocol.
  public static let sonySixaxis = Self(builtIn: "SonySixaxis")
  /// The Sony DualShock 4 protocol.
  public static let sonyDualShock4 = Self(builtIn: "SonyDualShock4")
  /// The Sony DualSense protocol.
  public static let sonyDualSense = Self(builtIn: "SonyDualSense")
  /// The Nintendo Switch protocol with a subcommand channel.
  public static let nintendoSwitch1 = Self(builtIn: "NintendoSwitch1")
  /// Nintendo Switch 2 controller (SDL `SDL_hidapi_switch2.c`): input report `0x05` after an init
  /// sequence on the vendor bulk interface, or the same state over its Bluetooth LE GATT link.
  public static let nintendoSwitch2 = Self(builtIn: "NintendoSwitch2")
  /// Wired Switch pad with a fixed HID input report and no subcommand channel (SDL
  /// `SwitchInputOnlyController`).
  public static let nintendoSwitchInputOnly = Self(builtIn: "NintendoSwitchInputOnly")
  /// The Valve Steam Controller protocol.
  public static let valveSteamController = Self(builtIn: "ValveSteamController")
  /// 2026 Steam Controller (SDL `SteamControllerTriton`): its own report IDs, settings feature
  /// report, and repeated rumble report.
  public static let valveSteamTriton = Self(builtIn: "ValveSteamTriton")
  /// Steam Deck built-in controller (SDL `SteamControllerNeptune`): its own state report,
  /// settings, watchdog, and rumble report.
  public static let valveSteamDeck = Self(builtIn: "ValveSteamDeck")
  /// The vendor protocol of third-party PS3 pads.
  public static let vendorPS3ThirdParty = Self(builtIn: "VendorPS3ThirdParty")
  /// The GameSir vendor protocol.
  public static let vendorGameSir = Self(builtIn: "VendorGameSir")
  /// The NVIDIA SHIELD controller vendor protocol.
  public static let vendorNVIDIAShield = Self(builtIn: "VendorNVIDIAShield")
  /// The Nintendo Wii Remote (and Wii U Pro Controller) over Bluetooth Classic HID.
  public static let nintendoWii = Self(builtIn: "NintendoWii")
  /// The Nintendo Wii U GameCube Controller Adapter: one HID device whose input report carries four
  /// controller ports.
  public static let nintendoGameCubeAdapter = Self(builtIn: "NintendoGameCubeAdapter")

  /// The family-specific `defaults.session` fields this family's driver reads.
  ///
  /// Its description sets exactly these and no other family-specific field.
  var sessionFields: Set<String> {
    switch self {
    case .nintendoSwitch1: ["subcommands"]
    case .nintendoSwitch2: ["commandChannel", "trailingStopPackets"]
    case .xboxGIP: ["namedPackets", "handshakeAttempts", "announceResendLimit"]
    case .valveSteamController: ["activation", "deactivation"]
    case .valveSteamTriton: ["activation", "deactivation"]
    case .valveSteamDeck: ["activation", "deactivation"]
    case .nintendoWii: ["wiiRemote"]
    default: []
    }
  }

  /// The general `defaults.session` keys this family uses beyond the rumble template, which
  /// `recordSections` governs: the keys its description may set.
  ///
  /// Its description lists exactly these as `sessionKeys`. HID startup writes run through one
  /// shared pipeline, so this names what the family uses, not what its driver reads itself.
  var generalSessionFields: Set<ProtocolDescription.SessionKey> {
    switch self {
    case .xboxXUSB, .nintendoSwitch1, .sonyDualShock4, .hidReportLayout: [.startup]
    case .xboxGIP, .nintendoSwitch2, .vendorGameSir: [.startup, .keepAlive]
    case .valveSteamTriton, .valveSteamDeck: [.keepAlive]
    default: []
    }
  }

  /// The parameter names this family's driver reads.
  ///
  /// Loading refuses a description that declares others, and the bundled descriptions declare
  /// exactly these, as a test checks.
  var readParameters: Set<String> {
    switch self {
    case .xboxGIP: ["shareButton"]
    case .sonyDualShock4: ["motionCalibration", "role", "motionScale"]
    case .sonyDualSense:
      ["maker", "unprobedSensors", "unprobedTouchpad", "forcedVibration", "role"]
    case .nintendoSwitch1: ["layout", "usbProtocol"]
    case .nintendoSwitch2: ["layout"]
    case .vendorPS3ThirdParty: ["hatSource"]
    case .vendorGameSir: ["innerGrips", "lightingMemory"]
    case .vendorNVIDIAShield: ["reportRevision"]
    default: []
    }
  }

  /// The stem of this family's description file in `Resources/Protocols`: the command-line
  /// spelling of the family, which is also the family's token in `ojd` output and arguments.
  public var descriptionFileStem: String { isDocumented ? rawValue : commandLineName }

  /// The family's token in `ojd` output and arguments.
  public var commandLineName: String { CommandLineName.kebab(rawValue) }

  /// The catalog key of the family's display name.
  ///
  /// Its last segment is the family token in lowerCamelCase (`sony-dual-shock4` is
  /// `sonyDualShock4`), the shape catalog key segments take.
  public var displayNameKey: String { "term.protocolFamily.\(keySegment)" }

  /// The family's name as a segment of a catalog key.
  private var keySegment: String { CommandLineName.keySegment(rawValue) }

  /// The family's name as the app shows it to a person, in the preferred language.
  public var displayName: String { displayName(in: protocolNameLocalization) }

  /// The family's name as `localization` resolves it.
  public func displayName(in localization: Localization) -> String {
    if isDocumented, let name = protocolDescription.displayName { return name }
    return localization.string(displayNameKey)
  }

  /// Whether a binding's name adds its variant: the family stores its variant in its records,
  /// because the transport does not tell every variant apart, and has more than one.
  public var namesVariant: Bool { storesVariant && variants.count > 1 }

  /// Implemented variants, as the family's description lists them.
  ///
  /// An empty list means the family has one contract.
  public var variants: [PhysicalProtocolVariantID] { protocolDescription.variants }

  /// Whether rows of this family, with this stored variant, are reached through raw USB.
  public func usesRawUSB(storedVariant: PhysicalProtocolVariantID?) -> Bool {
    protocolDescription.rawUSB.applies(to: storedVariant)
  }

  /// This family's bundled protocol description, which holds the facts its driver reads.
  var protocolDescription: ProtocolDescription {
    guard
      let description = ProtocolDescription.bundled[self]
        ?? DocumentedProtocolFamilies.description(named: rawValue)
    else {
      fatalError("[ProtocolDescription] No description for \(rawValue)")
    }
    return description
  }

  /// Whether this family's driver encodes rumble from a record's rumble template.
  var encodesRumbleTemplate: Bool { protocolDescription.recordSections.contains(.rumble) }

  /// Whether the driver of this family, stored variant and parameters encodes rumble from a
  /// record's rumble template: the family reads one, and GameSir reads it only for enhanced HID
  /// and NVIDIA SHIELD only for the 2015 controller.
  func readsRecordRumbleTemplate(
    variant: PhysicalProtocolVariantID?,
    parameters: ProtocolParameters
  ) -> Bool {
    guard encodesRumbleTemplate else { return false }
    switch self {
    case .vendorGameSir: return variant == .enhancedHID
    case .vendorNVIDIAShield: return parameters.reportRevision == .shield2015
    default: return true
    }
  }

  /// Whether records of this family need an input layout of their own: the driver reads one and
  /// the description supplies none.
  var requiresRecordInputLayout: Bool {
    let description = protocolDescription
    return description.recordSections.contains(.input) && description.inputLayouts == nil
  }

  /// Whether catalog records store this family's variant, as the family's description says;
  /// otherwise the family has one contract or classification derives the variant from the
  /// observed transport.
  public var storesVariant: Bool { protocolDescription.storesVariant }
}

/// Protocol variants.
///
/// Transport variants are derived from the observed transport; catalog records store only variants
/// that transport cannot decide (``PhysicalProtocolID/storesVariant``).
public enum PhysicalProtocolVariantID: String, CaseIterable, Sendable {
  /// The variant for a controller on USB.
  case usb = "USB"
  /// The variant for a controller on Bluetooth Classic.
  case bluetoothClassic = "BluetoothClassic"
  /// The variant for a controller on Bluetooth LE.
  case bluetoothLE = "BluetoothLE"
  /// The variant for a controller that presents a plain gamepad.
  case gamepad = "Gamepad"
  /// The variant for a wired controller.
  case wired = "Wired"
  /// The variant for a receiver that serves controllers.
  case receiver = "Receiver"
  /// The variant for a dongle that serves controllers.
  case dongle = "Dongle"
  /// The variant for controllers that use the vendor's enhanced HID reports.
  case enhancedHID = "EnhancedHID"

  /// The catalog key of the variant's display name.
  ///
  /// Its last segment is the variant's kebab-case spelling in lowerCamelCase (`EnhancedHID` is
  /// `enhancedHid`). The catalog holds the key for each variant of a family that names its variant
  /// (``PhysicalProtocolID/namesVariant``) and for no other variant.
  public var displayNameKey: String { "term.protocolVariant.\(keySegment)" }

  /// The variant's name as a segment of a catalog key.
  private var keySegment: String { CommandLineName.keySegment(rawValue) }
}

/// The resolver of protocol family and variant names.
///
/// Built once, so the Library search, which names every record on each keystroke, discovers the
/// packaged locales once.
private let protocolNameLocalization = Localization()

extension ProtocolBindingID {
  /// The binding's name as the app shows it to a person, in the preferred language: the family's
  /// name, with the variant's name when the family names its variant
  /// (``PhysicalProtocolID/namesVariant``), as in "Xbox 360 (XUSB), Receiver": the family stores
  /// its variant in its records, because the transport does not tell every variant apart, and has
  /// more than one.
  ///
  /// For any other family the name is the family's alone.
  public var displayName: String { displayName(in: protocolNameLocalization) }

  /// The binding's name as `localization` resolves it.
  public func displayName(in localization: Localization) -> String {
    let family = protocolID.displayName(in: localization)
    guard let variant, protocolID.namesVariant else { return family }
    return localization.string(
      "term.protocolBinding.familyWithVariant",
      family,
      localization.string(variant.displayNameKey)
    )
  }
}
