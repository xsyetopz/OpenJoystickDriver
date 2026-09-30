import Foundation

/// Physical protocol families with an implemented OJD parser.
///
/// The taxonomy in the protocol specification names more families; a family joins
/// this enum only when a driver for it exists.
public enum PhysicalProtocolID: String, CaseIterable, Codable, Sendable {
  case hidDescriptor = "hid.descriptor"
  case xboxXID = "xbox.xid"
  case xboxXUSB = "xbox.xusb"
  case xboxGIP = "xbox.gip"
  case sonySixaxis = "sony.sixaxis"
  case sonyDualShock4 = "sony.dualshock4"
  case sonyDualSense = "sony.dualsense"
  case nintendoSwitch1 = "nintendo.switch1"
  case valveSteamController = "valve.steam-controller"
  case vendorFlydigi = "vendor.flydigi"
  case vendorGameSir = "vendor.gamesir"
  case genericByteLayout = "generic.byte-layout"

  /// Implemented variants. An empty list means the family has one contract.
  public var variants: [PhysicalProtocolVariantID] {
    switch self {
    case .hidDescriptor, .vendorFlydigi, .genericByteLayout: []
    case .xboxXID: [.gamepad]
    case .xboxXUSB: [.wired, .receiver]
    case .xboxGIP: [.usb]
    case .sonySixaxis, .sonyDualShock4, .sonyDualSense, .nintendoSwitch1: [.usb, .bluetoothClassic]
    case .valveSteamController: [.wired, .dongle]
    case .vendorGameSir: [.usb, .enhancedHID]
    }
  }

  /// Whether rows of this family, with this stored variant, are reached through raw USB.
  public func usesRawUSB(storedVariant: PhysicalProtocolVariantID?) -> Bool {
    switch self {
    case .xboxXID, .xboxXUSB, .xboxGIP: true
    case .vendorGameSir: storedVariant == .usb
    case .hidDescriptor, .sonySixaxis, .sonyDualShock4, .sonyDualSense, .nintendoSwitch1,
      .valveSteamController, .vendorFlydigi, .genericByteLayout:
      false
    }
  }

  /// Whether catalog records store this family's variant; otherwise the family has one
  /// contract or classification derives the variant from the observed transport.
  public var storesVariant: Bool {
    switch self {
    case .xboxXID, .xboxXUSB, .valveSteamController, .vendorGameSir: true
    case .hidDescriptor, .xboxGIP, .sonySixaxis, .sonyDualShock4, .sonyDualSense, .nintendoSwitch1,
      .vendorFlydigi, .genericByteLayout:
      false
    }
  }
}

/// Protocol variants. Transport variants are derived from the observed transport;
/// catalog records store only variants that transport cannot decide
/// (``PhysicalProtocolID/storesVariant``).
public enum PhysicalProtocolVariantID: String, Sendable {
  case usb
  case bluetoothClassic = "bluetooth-classic"
  case gamepad
  case wired
  case receiver
  case dongle
  case enhancedHID = "enhanced-hid"
}

/// Machine-readable reasons a device is not bound.
public enum ProtocolBindingReason: String, CaseIterable, Codable, Error, Sendable {
  case noProtocolMatch = "no-protocol-match"
  case ambiguousProtocolMatch = "ambiguous-protocol-match"
  case interfaceContractMismatch = "interface-contract-mismatch"
  case descriptorContractMismatch = "descriptor-contract-mismatch"
  case packetContractMismatch = "packet-contract-mismatch"
  case unsupportedProtocolVariant = "unsupported-protocol-variant"
  case unsupportedTransportVariant = "unsupported-transport-variant"
  case requiredInitializationFailed = "required-initialization-failed"
  case catalogConflict = "catalog-conflict"
  case virtualProfileUnavailable = "virtual-profile-unavailable"
}

/// Observed facts that supported a binding.
public enum ProtocolPredicate: String, Codable, Sendable {
  case catalogIdentity = "catalog-identity"
  case catalogAccessPath = "catalog-access-path"
  case hostTransport = "host-transport"
  case interfaceSignature = "interface-signature"
  /// The device descriptor's class triple on an unconfigured device with no interface facts.
  case deviceClassSignature = "device-class-signature"
  case interruptEndpointPair = "interrupt-endpoint-pair"
  case hidDescriptorContract = "hid-descriptor-contract"
}

/// One selected protocol for one physical device.
public struct ProtocolBinding: Equatable, Sendable {
  public enum Rule: String, Codable, Sendable {
    case catalogRecord = "catalog-record"
    case interfaceSignature = "interface-signature"
    case hidDescriptor = "hid-descriptor"
  }

  public let protocolID: PhysicalProtocolID
  public let variant: PhysicalProtocolVariantID?
  public let accessBackend: DeviceAccessBackend
  public let interfaceNumber: UInt8?
  public let rule: Rule
  public let matchedPredicates: [ProtocolPredicate]
  public let record: DeviceRuntimeProfile?

  public var id: ProtocolBindingID { ProtocolBindingID(protocolID, variant: variant) }
}

public enum ProtocolClassification: Equatable, Sendable {
  case bound(ProtocolBinding)
  /// `rejected` names the family that matched and then failed its contract; nil when none matched.
  case unsupported(ProtocolBindingReason, rejected: ProtocolBindingResult.RejectedCandidate? = nil)
  case conflict(ProtocolBindingReason, candidates: [PhysicalProtocolID])
}

/// Deterministic protocol selection from observed facts. It performs no I/O.
///
/// Precedence: exact catalog record, then a protocol-standard USB interface
/// signature (the device-descriptor GIP triple only when an unconfigured device
/// exposes no interface facts), then the `hid.descriptor` contract.
/// `hid.descriptor` always requires the descriptor contract, including for catalog records.
/// A validation failure never falls through to a lower level.
enum ProtocolClassifier {
  static func classify(
    _ device: PhysicalDevice,
    backend: DeviceAccessBackend,
    catalog: DeviceCatalog
  ) -> ProtocolClassification {
    let interfaces = (device.interfaces ?? []).sorted {
      ($0.interfaceNumber ?? .max, $0.alternateSetting ?? .max) < (
        $1.interfaceNumber ?? .max, $1.alternateSetting ?? .max
      )
    }
    if let vendorID = device.vendorID, let productID = device.productID,
      let record = catalog.record(for: DeviceIdentifier(vendorID: vendorID, productID: productID))
    {
      return bind(record, interfaces: interfaces, backend: backend)
    }
    if let result = classifySignature(interfaces, backend: backend)
      ?? classifyDeviceSignature(device, backend: backend)
    {
      return result
    }
    guard backend == .ioHID else { return .unsupported(.noProtocolMatch) }
    guard let interface = descriptorInterface(interfaces) else {
      return .unsupported(.descriptorContractMismatch)
    }
    return .bound(
      ProtocolBinding(
        protocolID: .hidDescriptor,
        variant: nil,
        accessBackend: backend,
        interfaceNumber: interface.interfaceNumber,
        rule: .hidDescriptor,
        matchedPredicates: [.hidDescriptorContract],
        record: nil
      )
    )
  }

  private static func bind(
    _ record: DeviceRuntimeProfile,
    interfaces: [PhysicalInterfaceSignature],
    backend: DeviceAccessBackend
  ) -> ProtocolClassification {
    let isRawUSB = backend != .ioHID
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
    let variants = record.physicalProtocolID.variants
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
      : interfaces.count == 1 ? interfaces[0].interfaceNumber : nil
    // A catalog row adds identity to `hid.descriptor`; it never replaces validation.
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

  /// The first interface whose observed HID facts satisfy the descriptor contract.
  private static func descriptorInterface(
    _ interfaces: [PhysicalInterfaceSignature]
  ) -> PhysicalInterfaceSignature? {
    interfaces.first { HIDDescriptorContract.violation(in: $0.hidLayout) == nil }
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
    case .bluetoothLE, .proprietaryRadioReceiver: return nil
    }
  }

  struct InterfaceSignature: Equatable {
    let protocolID: PhysicalProtocolID
    let variant: PhysicalProtocolVariantID
    let interfaceClass: UInt8
    let interfaceSubclass: UInt8
    let interfaceProtocol: UInt8
    /// GIP shares its triple across interfaces; only this interface carries data.
    let requiredInterfaceNumber: UInt8?

    func matches(_ interface: PhysicalInterfaceSignature) -> Bool {
      interface.interfaceClass == interfaceClass && interface.interfaceSubclass == interfaceSubclass
        && interface.interfaceProtocol == interfaceProtocol
    }
  }

  /// Pinned against Linux `xpad.c` at the `ControllerSources.lock.json` commit:
  /// the `'X','B',0` table entry, `XPAD_XBOX360_VENDOR` (subclass 93, protocols 1
  /// and 129), `XPAD_XBOXONE_VENDOR` (subclass 71, protocol 208), the GIP data
  /// interface number, and the interrupt IN+OUT endpoint requirement in `xpad_probe`.
  static let signatures = [
    InterfaceSignature(
      protocolID: .xboxXID,
      variant: .gamepad,
      interfaceClass: 0x58,
      interfaceSubclass: 0x42,
      interfaceProtocol: 0x00,
      requiredInterfaceNumber: nil
    ),
    InterfaceSignature(
      protocolID: .xboxXUSB,
      variant: .wired,
      interfaceClass: 0xFF,
      interfaceSubclass: 0x5D,
      interfaceProtocol: 0x01,
      requiredInterfaceNumber: nil
    ),
    InterfaceSignature(
      protocolID: .xboxXUSB,
      variant: .receiver,
      interfaceClass: 0xFF,
      interfaceSubclass: 0x5D,
      interfaceProtocol: 0x81,
      requiredInterfaceNumber: nil
    ),
    InterfaceSignature(
      protocolID: .xboxGIP,
      variant: .usb,
      interfaceClass: 0xFF,
      interfaceSubclass: 0x47,
      interfaceProtocol: 0xD0,
      requiredInterfaceNumber: 0
    ),
  ]

  private static func classifySignature(
    _ interfaces: [PhysicalInterfaceSignature],
    backend: DeviceAccessBackend
  ) -> ProtocolClassification? {
    var matched: [InterfaceSignature] = []
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
    // `hid.descriptor`.
    guard backend != .ioHID else {
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

  static func hasInterruptPair(_ interface: PhysicalInterfaceSignature) -> Bool {
    let endpoints = interface.endpoints ?? []
    return [USBEndpointDirection.in, .out].allSatisfy { direction in
      endpoints.contains {
        $0.address != nil && $0.transferType == .interrupt && $0.direction == direction
      }
    }
  }
}
