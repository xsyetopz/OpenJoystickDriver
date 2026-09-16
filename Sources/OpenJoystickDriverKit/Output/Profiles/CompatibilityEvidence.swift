public enum CompatibilityEvidenceCatalog {
  public static let records: [CompatibilityEvidenceRecord] = [
    CompatibilityEvidenceRecord(
      vendorID: 0x11C1,
      productID: 0x5600,
      subfamily: .hid,
      physicalTransport: "wired",
      physicalMode: "generichid",
      connection: "usb",
      consumer: .unknown,
      identity: .appleGameController,
      evidence: .sourceBacked,
      reason: .selectedCatalogTuple
    ),
    CompatibilityEvidenceRecord(
      vendorID: 0x045E,
      productID: 0x02FD,
      subfamily: .gip,
      physicalTransport: "bluetooth",
      physicalMode: "gip",
      connection: "bluetooth",
      consumer: .sdlHIDAPI,
      identity: .genericHID,
      evidence: .reportedFailure,
      reason: .reportedConsumerFailure
    ),
    CompatibilityEvidenceRecord(
      vendorID: 0x3537,
      productID: 0x1010,
      subfamily: .gip,
      physicalTransport: "wired",
      physicalMode: "gip",
      connection: "usb",
      consumer: .appleGameController,
      identity: .appleGameController,
      evidence: .hardwareVerified,
      reason: .selectedCatalogTuple
    ),
    CompatibilityEvidenceRecord(
      vendorID: 0x3537,
      productID: 0x1010,
      subfamily: .gip,
      physicalTransport: "wired",
      physicalMode: "gip",
      connection: "usb",
      consumer: .sdlHIDAPI,
      identity: .appleGameController,
      evidence: .sourceBacked,
      reason: .selectedCatalogTuple
    ),
  ]
  public static func resolution(
    for device: ApplicationServiceDeviceDescription,
    consumer: CompatibilityConsumerFamily
  ) -> AutomaticCompatibilityResolution {
    let subfamily = AutomaticCompatibilityResolver.subfamily(for: device)
    let transport = device.connection.lowercased() == "bluetooth" ? "bluetooth" : "wired"
    let mode = device.parser.lowercased()
    if let record = records.first(where: {
      $0.vendorID == device.vendorID && $0.productID == device.productID
        && $0.subfamily == subfamily && $0.consumer == consumer && $0.physicalTransport == transport
        && $0.physicalMode == mode && $0.connection == device.connection.lowercased()
    }) {
      return AutomaticCompatibilityResolution(
        identity: record.identity,
        subfamily: subfamily,
        consumer: consumer,
        evidence: record.evidence,
        reason: record.reason
      )
    }
    if let route = CompatibilityProtocolBackendCatalog.route(for: subfamily) {
      let explicit = route.containsExplicit(vendorID: device.vendorID, productID: device.productID)
      return AutomaticCompatibilityResolution(
        identity: route.selectableIdentity,
        subfamily: subfamily,
        consumer: consumer,
        evidence: route.evidence,
        reason: explicit ? .selectedExplicitIdentity : .selectedFamilyIdentity
      )
    }
    if subfamily == .hid,
      let dialect = CompatibilityProtocolBackendCatalog.hidDialectRoute(for: device)
    {
      let explicit = dialect.containsExplicit(
        vendorID: device.vendorID,
        productID: device.productID
      )
      return AutomaticCompatibilityResolution(
        identity: dialect.selectableIdentity,
        subfamily: subfamily,
        consumer: consumer,
        evidence: dialect.evidence,
        reason: explicit ? .selectedExplicitIdentity : .selectedFamilyIdentity
      )
    }
    return AutomaticCompatibilityResolution(
      identity: .genericHID,
      subfamily: subfamily,
      consumer: consumer,
      evidence: .unavailable,
      reason: consumer == .unknown ? .unknownConsumer : .noAdjacentIdentity
    )
  }
}

public enum AutomaticCompatibilityResolver {
  public static func subfamily(
    for device: ApplicationServiceDeviceDescription
  ) -> PhysicalProtocolSubfamily {
    switch device.protocolVariant {
    case .xid: return .xid
    case .xbox360, .xbox360Wireless, .gameSirG7ProUSB: return .xusb
    case .xboxOne, .xboxAdaptiveJoystick: return .gip
    case .dualShock3, .dualShock4, .dualSense, .switchPro, .steamController, .flydigi,
      .xboxBluetoothHID, .flydigiVendor, .gameSirEnhancedHID, .genericHID, .unknown:
      return .hid
    }
  }

  public static func resolve(
    for device: ApplicationServiceDeviceDescription,
    consumer: CompatibilityConsumerFamily
  ) -> AutomaticCompatibilityResolution {
    CompatibilityEvidenceCatalog.resolution(for: device, consumer: consumer)
  }

  public static func resolve(
    for device: ApplicationServiceDeviceDescription
  ) -> AutomaticCompatibilityResolution { resolve(for: device, consumer: .unknown) }

  public static func target(
    for device: ApplicationServiceDeviceDescription,
    consumer: CompatibilityConsumerFamily
  ) -> AutomaticCompatibilityTarget {
    if let browserTarget = browserTarget(for: device, consumer: consumer) { return browserTarget }
    let resolution = resolve(for: device, consumer: consumer)
    return AutomaticCompatibilityTarget(identity: resolution.identity)
  }

  private static func browserTarget(
    for device: ApplicationServiceDeviceDescription,
    consumer: CompatibilityConsumerFamily
  ) -> AutomaticCompatibilityTarget? {
    let xboxFallback: AutomaticCompatibilityTarget
    switch consumer {
    case .blinkGamepad, .webkitGamepad, .unknownBrowserGamepad: xboxFallback = .appleGameController
    case .geckoGamepad:
      xboxFallback = AutomaticCompatibilityTarget(
        identity: .appleGameController,
        reportVariant: .geckoXboxOneS
      )
    case .genericHID, .sdlHIDAPI, .appleGameController, .xbox360HID, .unknown: return nil
    }

    switch device.protocolVariant {
    case .dualShock4: return consumer == .unknownBrowserGamepad ? .appleGameController : .dualShock4
    case .dualSense: return consumer == .unknownBrowserGamepad ? .appleGameController : .dualSense
    case .xid, .xbox360, .xbox360Wireless, .xboxOne, .xboxAdaptiveJoystick, .dualShock3, .switchPro,
      .steamController, .flydigi, .flydigiVendor, .xboxBluetoothHID, .gameSirG7ProUSB,
      .gameSirEnhancedHID, .genericHID, .unknown:
      return xboxFallback
    }
  }
}
