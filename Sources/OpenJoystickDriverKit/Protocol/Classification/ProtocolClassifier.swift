import Foundation

/// Physical protocol families with an implemented OJD parser.
///
/// The taxonomy in the protocol specification names more families; a family joins
/// this enum only when a driver for it exists.
public enum PhysicalProtocolID: String, CaseIterable, Codable, Sendable {
  /// Controllers recognised from their HID report descriptor alone.
  case hidDescriptor = "HIDDescriptor"
  /// A fixed input-report layout from the controller record (``ControllerInputLayouts``).
  case hidReportLayout = "HIDReportLayout"
  /// The original Xbox controller protocol (XID).
  case xboxXID = "XboxXID"
  /// The Xbox 360 controller protocol (XUSB).
  case xboxXUSB = "XboxXUSB"
  /// The Xbox One and later controller protocol (GIP).
  case xboxGIP = "XboxGIP"
  /// The Sony Sixaxis and DualShock 3 protocol.
  case sonySixaxis = "SonySixaxis"
  /// The Sony DualShock 4 protocol.
  case sonyDualShock4 = "SonyDualShock4"
  /// The Sony DualSense protocol.
  case sonyDualSense = "SonyDualSense"
  /// The Nintendo Switch protocol with a subcommand channel.
  case nintendoSwitch1 = "NintendoSwitch1"
  /// Nintendo Switch 2 controller (SDL `SDL_hidapi_switch2.c`): input report `0x05` after an init
  /// sequence on the vendor bulk interface, or the same state over its Bluetooth LE GATT link.
  case nintendoSwitch2 = "NintendoSwitch2"
  /// Wired Switch pad with a fixed HID input report and no subcommand channel (SDL
  /// `SwitchInputOnlyController`).
  case nintendoSwitchInputOnly = "NintendoSwitchInputOnly"
  /// The Valve Steam Controller protocol.
  case valveSteamController = "ValveSteamController"
  /// 2026 Steam Controller (SDL `SteamControllerTriton`): its own report IDs, settings feature
  /// report, and repeated rumble report.
  case valveSteamTriton = "ValveSteamTriton"
  /// Steam Deck built-in controller (SDL `SteamControllerNeptune`): its own state report,
  /// settings, watchdog, and rumble report.
  case valveSteamDeck = "ValveSteamDeck"
  /// The Flydigi vendor protocol.
  case vendorFlydigi = "VendorFlydigi"
  /// The vendor protocol of third-party PS3 pads.
  case vendorPS3ThirdParty = "VendorPS3ThirdParty"
  /// The GameSir vendor protocol.
  case vendorGameSir = "VendorGameSir"
  /// The NVIDIA SHIELD controller vendor protocol.
  case vendorNVIDIAShield = "VendorNVIDIAShield"
  /// The Nintendo Wii Remote (and Wii U Pro Controller) over Bluetooth Classic HID.
  case nintendoWii = "NintendoWii"

  /// The family-specific `defaults.session` fields this family's driver reads.
  ///
  /// Its description sets exactly these and no other family-specific field.
  var sessionFields: Set<String> {
    switch self {
    case .nintendoSwitch1: ["subcommands"]
    case .nintendoSwitch2: ["commandChannel", "trailingStopPackets"]
    case .xboxGIP: ["namedPackets", "handshakeAttempts", "announceResendLimit"]
    case .xboxXUSB: ["receiverInquiryResendLimit"]
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
    case .xboxXUSB, .nintendoSwitch1, .sonyDualShock4: [.startup]
    case .xboxGIP, .nintendoSwitch2, .vendorGameSir: [.startup, .keepAlive]
    case .valveSteamTriton, .valveSteamDeck: [.keepAlive]
    case .hidDescriptor, .hidReportLayout, .xboxXID, .sonySixaxis, .sonyDualSense,
      .nintendoSwitchInputOnly, .valveSteamController, .vendorFlydigi, .vendorPS3ThirdParty,
      .vendorNVIDIAShield, .nintendoWii:
      []
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
  public var descriptionFileStem: String { commandLineName }

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
    localization.string(displayNameKey)
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
    guard let description = ProtocolDescription.bundled[self] else {
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

/// Machine-readable reasons a device is not bound.
public enum ProtocolBindingReason: String, CaseIterable, Codable, Error, Sendable {
  /// No protocol family matches the device.
  case noProtocolMatch = "NoProtocolMatch"
  /// More than one protocol family matches the device.
  case ambiguousProtocolMatch = "AmbiguousProtocolMatch"
  /// The device's interfaces do not meet the family's interface contract.
  case interfaceContractMismatch = "InterfaceContractMismatch"
  /// The device's HID descriptor does not meet the family's descriptor contract.
  case descriptorContractMismatch = "DescriptorContractMismatch"
  /// The family does not implement the variant.
  case unsupportedProtocolVariant = "UnsupportedProtocolVariant"
  /// The family does not support the variant that the observed transport implies.
  case unsupportedTransportVariant = "UnsupportedTransportVariant"
  /// No virtual HID profile is available for the selected binding.
  case virtualProfileUnavailable = "VirtualProfileUnavailable"
  /// The host refused OJD's read of the device's USB configuration while it reported another
  /// exclusive owner of the device.
  case deviceInUse = "DeviceInUse"
  /// The device's USB configuration could not be read, and nothing OJD observes clears the cause
  /// before the device reconnects.
  case configurationUnreadable = "ConfigurationUnreadable"
}

extension ProtocolBindingReason {
  /// The catalog key of the sentence that tells a person why the device is unserved and how to free
  /// it.
  ///
  /// Nil for a reason that the person cannot act on, which the app and `ojd` show by its ID alone.
  public var explanationKey: String? {
    switch self {
    case .deviceInUse: return "ui.controllers.deviceInUse"
    case .configurationUnreadable: return "ui.controllers.configurationUnreadable"
    case .noProtocolMatch, .ambiguousProtocolMatch, .interfaceContractMismatch,
      .descriptorContractMismatch, .unsupportedProtocolVariant, .unsupportedTransportVariant,
      .virtualProfileUnavailable:
      return nil
    }
  }
}

/// Observed facts that supported a binding.
public enum ProtocolPredicate: String, Codable, Sendable {
  /// The catalog names the device's vendor and product.
  case catalogIdentity = "CatalogIdentity"
  /// The catalog access path of the record matches the device.
  case catalogAccessPath = "CatalogAccessPath"
  /// The host transport matches.
  case hostTransport = "HostTransport"
  /// An interface has the family's class signature.
  case interfaceSignature = "InterfaceSignature"
  /// The device descriptor's class triple on an unconfigured device with no interface facts.
  case deviceClassSignature = "DeviceClassSignature"
  /// The device has the family's pair of interrupt endpoints.
  case interruptEndpointPair = "InterruptEndpointPair"
  /// The HID descriptor meets ``HIDDescriptorContract``.
  case hidDescriptorContract = "HIDDescriptorContract"
}

/// One selected protocol for one physical device.
public struct ProtocolBinding: Equatable, Sendable {
  /// The rule that selected the protocol.
  public enum Rule: String, Codable, Sendable {
    /// A catalog record named the protocol.
    case catalogRecord = "CatalogRecord"
    /// An interface class signature identified the protocol.
    case interfaceSignature = "InterfaceSignature"
    /// The HID descriptor contract identified the protocol.
    case hidDescriptor = "HIDDescriptor"
    /// The HID descriptor contract identified the protocol and an SDL_GameControllerDB line maps
    /// its inputs.
    case sdlGameControllerDB = "SDLGameControllerDB"
  }

  /// The protocol family.
  public let protocolID: PhysicalProtocolID
  /// The variant of the family; nil when the family has none.
  public let variant: PhysicalProtocolVariantID?
  /// The route the device is accessed over.
  public let accessBackend: DeviceAccessBackend
  /// The number of the interface the protocol drives; nil when the device is not split by
  /// interface.
  public let interfaceNumber: UInt8?
  /// The rule that selected the protocol.
  public let rule: Rule
  /// The facts that supported the binding.
  public let matchedPredicates: [ProtocolPredicate]
  /// The catalog record that applied; nil when none did.
  public let record: DeviceRuntimeProfile?
  /// What the database gave a HID pad without a record; nil for a record or another family.
  var sdl: SDLBindingResolution?

  /// Where the HID usage map of a `HIDDescriptor` binding comes from; nil for another family.
  public var inputMapping: InputMapping? {
    guard protocolID == .hidDescriptor else { return nil }
    return sdl?.inputMapping ?? (record == nil ? .standardHIDUsageMap : .record)
  }

  /// The binding as a family and variant.
  public var id: ProtocolBindingID { ProtocolBindingID(protocolID, variant: variant) }
}

/// The outcome of classifying one device.
public enum ProtocolClassification: Equatable, Sendable {
  /// The device is bound to a protocol.
  case bound(ProtocolBinding)
  /// `rejected` names the family that matched and then failed its contract; nil when none matched.
  case unsupported(ProtocolBindingReason, rejected: ProtocolBindingResult.RejectedCandidate? = nil)
  /// More than one protocol family claims the device.
  case conflict(ProtocolBindingReason, candidates: [PhysicalProtocolID])
}

/// Deterministic protocol selection from observed facts.
///
/// It performs no I/O.
///
/// Precedence: exact catalog record, then a protocol-standard USB interface
/// signature (the device-descriptor GIP triple only when an unconfigured device
/// exposes no interface facts), then the `HIDDescriptor` contract.
/// `HIDDescriptor` always requires the descriptor contract, including for catalog records.
/// A validation failure never falls through to a lower level. One exception: a record of one
/// Xbox USB family whose device exposes only the other family's interface signature binds by
/// that signature.
enum ProtocolClassifier {
  /// Selects the protocol family, variant and interface that drive `device` over `backend`, or
  /// says why none does.
  ///
  /// `modeID` names the mode of the matching catalog record to bind; nil binds the default mode.
  /// - Returns: ``ProtocolClassification`` as a binding, as unsupported when no family fits, or as
  ///   a conflict when more than one fits.
  static func classify(
    _ device: PhysicalDevice,
    backend: DeviceAccessBackend,
    catalog: DeviceCatalog,
    modeID: String? = nil,
    database: SDLGameControllerDatabase = .bundled
  ) -> ProtocolClassification {
    let interfaces = (device.interfaces ?? []).sorted {
      ($0.interfaceNumber ?? .max, $0.alternateSetting ?? .max) < (
        $1.interfaceNumber ?? .max, $1.alternateSetting ?? .max
      )
    }
    if let vendorID = device.vendorID, let productID = device.productID,
      let record = catalog.record(
        for: ControllerModelID(vendorID: vendorID, productID: productID),
        modeID: modeID
      )
    {
      return otherXboxFamilyBinding(for: record, interfaces: interfaces, backend: backend)
        ?? bind(record, interfaces: interfaces, backend: backend)
    }
    if let result = classifySignature(interfaces, backend: backend)
      ?? classifyDeviceSignature(device, backend: backend)
    {
      return result
    }
    guard !backend.usesRawUSB else { return .unsupported(.noProtocolMatch) }
    guard let interface = descriptorInterface(interfaces) else {
      guard let line = database.match(for: device) else {
        return .unsupported(.descriptorContractMismatch)
      }
      return .unsupported(
        .descriptorContractMismatch,
        rejected: ProtocolBindingResult.RejectedCandidate(
          protocolID: .hidDescriptor,
          reason: .descriptorContractMismatch,
          inputMapping: InputMapping(
            source: .none,
            guid: line.guid.description,
            match: line.tier,
            unmapped: [],
            rejection: nil
          )
        )
      )
    }
    let resolution = database.resolve(device: device, interface: interface)
    return .bound(
      ProtocolBinding(
        protocolID: .hidDescriptor,
        variant: nil,
        accessBackend: backend,
        interfaceNumber: interface.interfaceNumber,
        rule: resolution.usageMap == nil ? .hidDescriptor : .sdlGameControllerDB,
        matchedPredicates: [.hidDescriptorContract],
        record: nil,
        sdl: resolution
      )
    )
  }

  /// Binds a catalog `record` to the interfaces and access path that `backend` observed.
  ///
  /// Rejects the record when its raw-USB use differs from the backend, when the transport variant
  /// cannot be told, or, for a `HIDDescriptor` record, when no interface passes the descriptor
  /// contract.
  private static func bind(
    _ record: DeviceRuntimeProfile,
    interfaces: [PhysicalInterfaceSignature],
    backend: DeviceAccessBackend
  ) -> ProtocolClassification {
    let isRawUSB = backend.usesRawUSB
    func reject(_ reason: ProtocolBindingReason) -> ProtocolClassification {
      .unsupported(
        reason,
        rejected: ProtocolBindingResult.RejectedCandidate(
          protocolID: record.physicalProtocolID,
          reason: reason,
          catalogRecordID: record.recordID
        )
      )
    }
    guard record.usesRawUSB == isRawUSB else { return reject(.unsupportedTransportVariant) }
    var predicates: [ProtocolPredicate] = [.catalogIdentity, .catalogAccessPath]
    let variants = transportVariants(of: record)
    let variant: PhysicalProtocolVariantID?
    if let stored = record.physicalProtocolVariant {
      variant = stored
    } else if variants.isEmpty {
      variant = nil
    } else {
      let observed = isRawUSB ? .usb : hostTransportVariant(interfaces)
      guard let observed, variants.contains(observed) else {
        return reject(.unsupportedTransportVariant)
      }
      variant = observed
      predicates.append(.hostTransport)
    }
    var interfaceNumber =
      isRawUSB
      ? record.transportProfile.interfaceNumber
      : boundInterfaceNumber(of: record, in: interfaces)
    // A catalog row adds identity to `HIDDescriptor`; it never replaces validation.
    if record.physicalProtocolID == .hidDescriptor {
      guard let interface = descriptorInterface(interfaces) else {
        return reject(.descriptorContractMismatch)
      }
      interfaceNumber = interface.interfaceNumber
      predicates.append(.hidDescriptorContract)
    }
    return .bound(
      ProtocolBinding(
        protocolID: record.physicalProtocolID,
        variant: variant,
        accessBackend: backend,
        interfaceNumber: interfaceNumber,
        rule: .catalogRecord,
        matchedPredicates: predicates,
        record: record
      )
    )
  }

  /// The signature binding of a device whose record names one Xbox USB family but whose interfaces
  /// carry only the other's.
  ///
  /// One VID:PID can ship either firmware mode (8BitDo `2dc8:3106` is XUSB in Linux `xpad.c` and
  /// GIP in SDL `controller_list.h`), and the claimed interface class is what the device speaks.
  /// Nil when the record's own signature is present.
  private static func otherXboxFamilyBinding(
    for record: DeviceRuntimeProfile,
    interfaces: [PhysicalInterfaceSignature],
    backend: DeviceAccessBackend
  ) -> ProtocolClassification? {
    let xboxUSB: Set<PhysicalProtocolID> = [.xboxXUSB, .xboxGIP]
    guard xboxUSB.contains(record.physicalProtocolID) else { return nil }
    let observed = Set(
      signatures.filter { signature in interfaces.contains(where: signature.matches) }.map(
        \.protocolID
      )
    )
    guard !observed.contains(record.physicalProtocolID),
      !observed.isDisjoint(with: xboxUSB.subtracting([record.physicalProtocolID]))
    else { return nil }
    return classifySignature(interfaces, backend: backend)
  }

  /// The interface a HID record binds to: the lowest one inside the mode's `interface` range, or
  /// the only one when the record names no range.
  private static func boundInterfaceNumber(
    of record: DeviceRuntimeProfile,
    in interfaces: [PhysicalInterfaceSignature]
  ) -> UInt8? {
    guard let range = record.interfaceRange else {
      return interfaces.count == 1 ? interfaces[0].interfaceNumber : nil
    }
    return interfaces.compactMap(\.interfaceNumber).filter(range.contains).min()
  }

  /// The first interface whose observed HID facts satisfy the descriptor contract.
  private static func descriptorInterface(
    _ interfaces: [PhysicalInterfaceSignature]
  ) -> PhysicalInterfaceSignature? {
    interfaces.first { HIDDescriptorContract.violation(in: $0.hidLayout) == nil }
  }

  /// The family's variants this model has a link for: all of them, except for a Bluetooth-only
  /// Switch pad, whose USB link only charges it.
  private static func transportVariants(
    of record: DeviceRuntimeProfile
  ) -> [PhysicalProtocolVariantID] {
    let variants = record.physicalProtocolID.variants
    guard record.parameters.usbProtocol == .chargingOnly else { return variants }
    return variants.filter { $0 != .usb }
  }

  /// The single host transport shared by every interface; unknown when any is absent.
  private static func hostTransportVariant(
    _ interfaces: [PhysicalInterfaceSignature]
  ) -> PhysicalProtocolVariantID? {
    guard let transport = interfaces.first?.hostTransport,
      interfaces.allSatisfy({ $0.hostTransport == transport })
    else { return nil }
    switch transport {
    case .usb: return .usb
    case .bluetoothClassic: return .bluetoothClassic
    case .bluetoothLE: return .bluetoothLE
    case .proprietaryRadioReceiver: return nil
    }
  }

  /// Binds the protocol-standard USB interface signature that `interfaces` match, or nil when none
  /// matches.
  ///
  /// Signatures of different families conflict. A signature needs a raw-USB backend and an
  /// interface with an interrupt IN and OUT endpoint pair; HID access never binds one.
  private static func classifySignature(
    _ interfaces: [PhysicalInterfaceSignature],
    backend: DeviceAccessBackend
  ) -> ProtocolClassification? {
    var matched: [ProtocolInterfaceSignature] = []
    for interface in interfaces {
      for signature in signatures where signature.matches(interface) && !matched.contains(signature)
      { matched.append(signature) }
    }
    guard let signature = matched.first else { return nil }
    var candidates: [PhysicalProtocolID] = []
    for match in matched where !candidates.contains(match.protocolID) {
      candidates.append(match.protocolID)
    }
    // Different families conflict. Variants of one family resolve to the variant of the lowest
    // interface number, since interfaces are matched in that order.
    guard candidates.count == 1 else {
      return .conflict(.ambiguousProtocolMatch, candidates: candidates)
    }
    // These are raw-USB variants; HID access cannot drive them and must not reach
    // `HIDDescriptor`.
    guard backend.usesRawUSB else {
      return .unsupported(
        .unsupportedTransportVariant,
        rejected: ProtocolBindingResult.RejectedCandidate(
          protocolID: signature.protocolID,
          reason: .unsupportedTransportVariant
        )
      )
    }
    guard
      let interface = interfaces.first(where: {
        signature.matches($0)
          && (signature.requiredInterfaceNumber == nil
            || $0.interfaceNumber == signature.requiredInterfaceNumber)
          // Registry-only facts carry no endpoints; claimed-interface validation checks them.
          && ($0.endpoints == nil || hasInterruptPair($0))
      })
    else {
      return .unsupported(
        .interfaceContractMismatch,
        rejected: ProtocolBindingResult.RejectedCandidate(
          protocolID: signature.protocolID,
          reason: .interfaceContractMismatch
        )
      )
    }
    return .bound(
      ProtocolBinding(
        protocolID: signature.protocolID,
        variant: signature.variant,
        accessBackend: backend,
        interfaceNumber: interface.interfaceNumber,
        rule: .interfaceSignature,
        matchedPredicates: interface.endpoints == nil
          ? [.interfaceSignature] : [.interfaceSignature, .interruptEndpointPair],
        record: nil
      )
    )
  }

  /// Whether `interface` has an addressed interrupt IN endpoint and an addressed interrupt OUT
  /// endpoint.
  static func hasInterruptPair(_ interface: PhysicalInterfaceSignature) -> Bool {
    let endpoints = interface.endpoints ?? []
    return [USBEndpointDirection.in, .out].allSatisfy { direction in
      endpoints.contains {
        $0.address != nil && $0.transferType == .interrupt && $0.direction == direction
      }
    }
  }
}
