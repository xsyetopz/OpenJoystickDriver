import Foundation

/// One first-party official USB identity that a host stack already knows how to bind.
public struct CompatibilityUSBIdentity: Equatable, Hashable, Sendable {
  public let vendorID: UInt16
  public let productID: UInt16

  public init(vendorID: UInt16, productID: UInt16) {
    self.vendorID = vendorID
    self.productID = productID
  }
}

/// Wire family → first-party virtual identity. Consumer APIs (SDL, GameController,
/// Gamepad API) are not backends; they share this table.
public struct CompatibilityProtocolBackendRoute: Equatable, Sendable {
  public let subfamily: PhysicalProtocolSubfamily
  public let firstParty: CompatibilityUSBIdentity
  public let explicitIdentities: Set<CompatibilityUSBIdentity>
  public let deviceProfile: VirtualDeviceProfile?
  public let selectableIdentity: CompatibilityIdentity
  public let evidence: CompatibilityEvidenceStatus
  public let notes: String

  public var canPublish: Bool { deviceProfile != nil }

  public func containsExplicit(vendorID: UInt16, productID: UInt16) -> Bool {
    explicitIdentities.contains(CompatibilityUSBIdentity(vendorID: vendorID, productID: productID))
  }
}

/// Automatic compatibility: stay on the physical wire family, spoof the closest
/// official device when a virtual report format exists.
public enum CompatibilityProtocolBackendCatalog {
  public static let routes: [CompatibilityProtocolBackendRoute] = [
    publishable(
      .xusb,
      firstParty: xbox360WiredIdentity,
      explicit: [xbox360WiredIdentity],
      profile: .xbox360Wired,
      identity: .sdl2_3,
      notes: "Microsoft Xbox 360 Wired. XUSB clones spoof this official HIDAPI device."
    ),
    publishable(
      .gip,
      firstParty: xboxSeriesIdentity,
      explicit: [
        xboxSeriesIdentity,
        CompatibilityUSBIdentity(vendorID: 0x045E, productID: 0x0B00),
        CompatibilityUSBIdentity(vendorID: 0x045E, productID: 0x0B12),
        CompatibilityUSBIdentity(vendorID: 0x045E, productID: 0x02EA),
      ],
      profile: .xboxSeries,
      identity: .appleGameController,
      notes: "Microsoft Xbox Series Bluetooth HID. USB GIP clones spoof this official device. "
        + "045E:02FD is first-party but reported no SDL HIDAPI input."
    ),
    unimplemented(
      .xid,
      firstParty: CompatibilityUSBIdentity(vendorID: 0x045E, productID: 0x0202),
      notes: "XID is original Xbox USB, not HID. No virtual XID identity."
    ),
    unimplemented(
      .hid,
      firstParty: CompatibilityUSBIdentity(vendorID: 0x4F4A, productID: 0x4449),
      notes: "HID has no single family identity. DualShock 4, DualSense, and Switch Pro "
        + "are automatic only when the physical dialect matches. Other HID stays Generic HID."
    ),
  ]

  /// First-party HID dialects with packers. Automatic routing uses a dialect
  /// only when the physical device is already that dialect.
  public static let hidDialectRoutes: [CompatibilityProtocolBackendRoute] = [
    publishable(
      .hid,
      firstParty: dualShock4Identity,
      explicit: [
        dualShock4Identity,
        CompatibilityUSBIdentity(vendorID: 0x054C, productID: 0x05C4),
        CompatibilityUSBIdentity(vendorID: 0x054C, productID: 0x0BA0),
      ],
      profile: .dualShock4USB,
      identity: .dualShock4,
      notes: "Sony DualShock 4 USB. Automatic for DualShock 4 physical devices."
    ),
    publishable(
      .hid,
      firstParty: dualSenseIdentity,
      explicit: [
        dualSenseIdentity,
        CompatibilityUSBIdentity(vendorID: 0x054C, productID: 0x0DF2),
      ],
      profile: .dualSenseUSB,
      identity: .dualSense,
      notes: "Sony DualSense USB. Automatic for DualSense physical devices."
    ),
    publishable(
      .hid,
      firstParty: switchProIdentity,
      explicit: [switchProIdentity],
      profile: .switchProUSB,
      identity: .switchPro,
      notes: "Nintendo Switch Pro USB. Automatic for Switch Pro physical devices."
    ),
  ]

  public static func route(for subfamily: PhysicalProtocolSubfamily)
    -> CompatibilityProtocolBackendRoute?
  {
    routes.first { $0.subfamily == subfamily && $0.canPublish }
  }

  public static func hidDialectRoute(for device: ApplicationServiceDeviceDescription)
    -> CompatibilityProtocolBackendRoute?
  {
    hidDialectRoutes.first { route in
      guard route.canPublish else { return false }
      if route.containsExplicit(vendorID: device.vendorID, productID: device.productID) {
        return true
      }
      return route.selectableIdentity == identity(for: device.protocolVariant)
    }
  }

  public static func canSelect(
    _ identity: CompatibilityIdentity,
    for subfamily: PhysicalProtocolSubfamily
  ) -> Bool {
    let catalog = routes + hidDialectRoutes
    return catalog.contains {
      $0.selectableIdentity == identity && $0.subfamily == subfamily && $0.canPublish
    }
  }

  private static let xbox360WiredIdentity = CompatibilityUSBIdentity(
    vendorID: 0x045E,
    productID: 0x028E
  )
  private static let xboxSeriesIdentity = CompatibilityUSBIdentity(
    vendorID: 0x045E,
    productID: 0x0B13
  )
  private static let dualShock4Identity = CompatibilityUSBIdentity(
    vendorID: 0x054C,
    productID: 0x09CC
  )
  private static let dualSenseIdentity = CompatibilityUSBIdentity(
    vendorID: 0x054C,
    productID: 0x0CE6
  )
  private static let switchProIdentity = CompatibilityUSBIdentity(
    vendorID: 0x057E,
    productID: 0x2009
  )

  private static func publishable(
    _ subfamily: PhysicalProtocolSubfamily,
    firstParty: CompatibilityUSBIdentity,
    explicit: Set<CompatibilityUSBIdentity> = [],
    profile: VirtualDeviceProfile,
    identity: CompatibilityIdentity,
    notes: String
  ) -> CompatibilityProtocolBackendRoute {
    CompatibilityProtocolBackendRoute(
      subfamily: subfamily,
      firstParty: firstParty,
      explicitIdentities: explicit.union([firstParty]),
      deviceProfile: profile,
      selectableIdentity: identity,
      evidence: .sourceBacked,
      notes: notes
    )
  }

  private static func identity(for variant: ControllerProtocolVariant) -> CompatibilityIdentity? {
    switch variant {
    case .dualShock4: return .dualShock4
    case .dualSense: return .dualSense
    case .switchPro: return .switchPro
    default: return nil
    }
  }

  private static func unimplemented(
    _ subfamily: PhysicalProtocolSubfamily,
    firstParty: CompatibilityUSBIdentity,
    explicit: Set<CompatibilityUSBIdentity> = [],
    notes: String
  ) -> CompatibilityProtocolBackendRoute {
    CompatibilityProtocolBackendRoute(
      subfamily: subfamily,
      firstParty: firstParty,
      explicitIdentities: explicit.union([firstParty]),
      deviceProfile: nil,
      selectableIdentity: .genericHID,
      evidence: .unavailable,
      notes: notes
    )
  }
}
