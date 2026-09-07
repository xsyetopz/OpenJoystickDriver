import Foundation

public enum USBEndpointTransferType: String, Equatable, Sendable {
  case control
  case isochronous
  case bulk
  case interrupt
  case unknown
}

public enum USBEndpointDirection: String, Equatable, Sendable {
  case `in`
  case out
}

public enum ProtocolFamilyCandidate: String, Equatable, Sendable {
  case genericHID
  case xid
  case xusb
  case gip
  case unsupported
}

public enum ProtocolClassifierDisposition: String, Equatable, Sendable {
  case advisory
  case ambiguous
  case unsupported
}

public enum ProtocolPredicate: String, Equatable, Sendable {
  case interfaceZeroAlternateZero
  case vendorSpecificInterface
  case xidInterfaceIdentity
  case xusbInterfaceIdentity
  case gipInterfaceIdentity
  case completeInterruptPair
  case hidInterface
  case hidGamepadOrJoystickCollection
  case usableHIDLayout
}

public struct HIDLayoutSummary: Equatable, Sendable {
  public let hasGamePadOrJoystickCollection: Bool
  public let hasUsableElements: Bool
  public let descriptorFingerprint: String?

  public init(
    hasGamePadOrJoystickCollection: Bool,
    hasUsableElements: Bool,
    descriptorFingerprint: String? = nil
  ) {
    self.hasGamePadOrJoystickCollection = hasGamePadOrJoystickCollection
    self.hasUsableElements = hasUsableElements
    self.descriptorFingerprint = descriptorFingerprint
  }
}

public struct ControllerTransportObservation: Equatable, Sendable {
  public let vendorID: UInt16
  public let productID: UInt16
  public let version: UInt16?
  public let interfaces: [USBInterfaceTransportFacts]
  public let hidLayout: HIDLayoutSummary?

  public init(
    vendorID: UInt16,
    productID: UInt16,
    version: UInt16? = nil,
    interfaces: [USBInterfaceTransportFacts],
    hidLayout: HIDLayoutSummary? = nil
  ) {
    self.vendorID = vendorID
    self.productID = productID
    self.version = version
    self.interfaces = interfaces
    self.hidLayout = hidLayout
  }

  public init(
    device: USBTransportDevice,
    interfaces: [USBInterfaceTransportFacts],
    version: UInt16? = nil,
    hidLayout: HIDLayoutSummary? = nil
  ) {
    self.init(
      vendorID: device.vendorID,
      productID: device.productID,
      version: version,
      interfaces: interfaces,
      hidLayout: hidLayout
    )
  }
}

public struct ProtocolClassification: Equatable, Sendable {
  public let selected: ProtocolFamilyCandidate?
  public let conflictingCandidates: [ProtocolFamilyCandidate]
  public let matchedPredicates: [ProtocolPredicate]
  public let rejectedPredicates: [ProtocolPredicate]
  public let disposition: ProtocolClassifierDisposition

  public init(
    selected: ProtocolFamilyCandidate?,
    conflictingCandidates: [ProtocolFamilyCandidate] = [],
    matchedPredicates: [ProtocolPredicate],
    rejectedPredicates: [ProtocolPredicate],
    disposition: ProtocolClassifierDisposition
  ) {
    self.selected = selected
    self.conflictingCandidates = conflictingCandidates
    self.matchedPredicates = matchedPredicates
    self.rejectedPredicates = rejectedPredicates
    self.disposition = disposition
  }
}

public enum USBProtocolClassifier {
  public static func classify(_ observation: ControllerTransportObservation)
    -> ProtocolClassification
  {
    let interfaces = observation.interfaces
    let xid = interfaces.first(where: isXID)
    let xusb = interfaces.first(where: isXUSB)
    let gip = interfaces.first(where: isGIP)
    let hid = interfaces.first(where: isHID)
    var matches: [ProtocolPredicate] = []
    var rejections: [ProtocolPredicate] = []

    if xid != nil {
      matches += [.xidInterfaceIdentity, .completeInterruptPair]
    } else {
      rejections += [.xidInterfaceIdentity]
    }
    if xusb != nil {
      matches += [.interfaceZeroAlternateZero, .xusbInterfaceIdentity, .completeInterruptPair]
    } else {
      rejections += [.xusbInterfaceIdentity]
    }
    if gip != nil {
      matches += [.interfaceZeroAlternateZero, .gipInterfaceIdentity, .completeInterruptPair]
    } else {
      rejections += [.gipInterfaceIdentity]
    }
    if let hid, observation.hidLayout?.hasGamePadOrJoystickCollection == true,
      observation.hidLayout?.hasUsableElements == true
    {
      _ = hid
      matches += [.hidInterface, .hidGamepadOrJoystickCollection, .usableHIDLayout]
    } else {
      rejections += [.hidInterface, .hidGamepadOrJoystickCollection, .usableHIDLayout]
    }

    // Conflicting vendor-family signatures fail closed; otherwise the order is
    // deterministic and keeps vendor families ahead of descriptor-only HID.
    var vendorCandidates: [ProtocolFamilyCandidate] = []
    if xid != nil { vendorCandidates.append(.xid) }
    if xusb != nil { vendorCandidates.append(.xusb) }
    if gip != nil { vendorCandidates.append(.gip) }
    let selected: ProtocolFamilyCandidate? =
      vendorCandidates.count > 1
      ? nil
      : vendorCandidates.first
        ?? (hid != nil && observation.hidLayout?.hasGamePadOrJoystickCollection == true
          && observation.hidLayout?.hasUsableElements == true ? .genericHID : nil)
    let conflictingCandidates: [ProtocolFamilyCandidate] =
      vendorCandidates.count > 1 ? vendorCandidates : []
    return ProtocolClassification(
      selected: selected,
      conflictingCandidates: conflictingCandidates,
      matchedPredicates: unique(matches),
      rejectedPredicates: unique(rejections),
      disposition: conflictingCandidates.isEmpty
        ? (selected == nil ? .unsupported : .advisory) : .ambiguous
    )
  }

  /// Original Xbox XID: USB-IF class `'X'`, subclass `'B'`, protocol `0`.
  private static func isXID(_ interface: USBInterfaceTransportFacts) -> Bool {
    interface.interfaceClass == 0x58 && interface.interfaceSubclass == 0x42
      && interface.interfaceProtocol == 0x00 && hasInterruptPair(interface)
  }

  /// Xbox 360 XUSB: wired Krypton uses protocol `1`; wireless Argon adapters use `129`.
  private static func isXUSB(_ interface: USBInterfaceTransportFacts) -> Bool {
    interface.interfaceNumber == 0 && interface.alternateSetting == 0
      && interface.interfaceClass == 0xFF && interface.interfaceSubclass == 0x5D
      && (interface.interfaceProtocol == 0x01 || interface.interfaceProtocol == 0x81)
      && hasInterruptPair(interface)
  }

  private static func isGIP(_ interface: USBInterfaceTransportFacts) -> Bool {
    interface.interfaceNumber == 0 && interface.alternateSetting == 0
      && interface.interfaceClass == 0xFF && interface.interfaceSubclass == 0x47
      && interface.interfaceProtocol == 0xD0 && hasInterruptPair(interface)
  }

  private static func isHID(_ interface: USBInterfaceTransportFacts) -> Bool {
    interface.interfaceClass == 0x03
  }

  private static func hasInterruptPair(_ interface: USBInterfaceTransportFacts) -> Bool {
    interface.endpoints.contains { $0.transferType == .interrupt && $0.direction == .in }
      && interface.endpoints.contains { $0.transferType == .interrupt && $0.direction == .out }
  }

  private static func unique(_ predicates: [ProtocolPredicate]) -> [ProtocolPredicate] {
    var seen = Set<ProtocolPredicate>()
    return predicates.filter { seen.insert($0).inserted }
  }
}

public struct ProtocolReconciliation: Equatable, Sendable {
  public let knownVariant: ControllerProtocolVariant
  public let matchingPredicates: [ProtocolPredicate]
  public let conflictingPredicates: [ProtocolPredicate]

  public var hasConflict: Bool { !conflictingPredicates.isEmpty }
}

public enum KnownRecordProtocolReconciler {
  public static func reconcile(
    observation: ControllerTransportObservation,
    profile: DeviceRuntimeProfile
  ) -> ProtocolReconciliation {
    let classification = USBProtocolClassifier.classify(observation)
    let expected: ProtocolFamilyCandidate? =
      switch profile.protocolVariant {
      case .xid: .xid
      case .xbox360, .xbox360Wireless: .xusb
      case .xboxOne, .xboxAdaptiveJoystick: .gip
      case .genericHID, .dualShock3, .dualShock4, .dualSense, .steamController, .switchPro,
        .flydigi:
        .genericHID
      case .unknown: nil
      }
    let match = expected != nil && classification.selected == expected
    return ProtocolReconciliation(
      knownVariant: profile.protocolVariant,
      matchingPredicates: match ? classification.matchedPredicates : [],
      conflictingPredicates: expected != nil && classification.selected != nil && !match
        ? classification.matchedPredicates : []
    )
  }
}
