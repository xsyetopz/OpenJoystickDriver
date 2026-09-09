/// First-class compatibility profiles exposed by the user-space HID backend.
public struct CompatibilityOutputProfile: Equatable, Sendable {
  public let identity: CompatibilityIdentity
  public let deviceProfile: VirtualDeviceProfile
  public let displayName: String
  public let notes: String
  public let isHardwareSpoof: Bool
  public let emitsXboxGuideReport: Bool
  public let evidence: CompatibilityEvidenceStatus
  public let consumerFamily: CompatibilityConsumerFamily
  public let automaticallyRecommended: Bool
  public let evidenceByConsumer: [CompatibilityConsumerFamily: CompatibilityEvidenceStatus]

  public init(
    identity: CompatibilityIdentity,
    deviceProfile: VirtualDeviceProfile,
    displayName: String,
    notes: String,
    isHardwareSpoof: Bool,
    emitsXboxGuideReport: Bool,
    evidence: CompatibilityEvidenceStatus = .sourceBacked,
    consumerFamily: CompatibilityConsumerFamily,
    automaticallyRecommended: Bool = false,
    evidenceByConsumer: [CompatibilityConsumerFamily: CompatibilityEvidenceStatus] = [:]
  ) {
    self.identity = identity
    self.deviceProfile = deviceProfile
    self.displayName = displayName
    self.notes = notes
    self.isHardwareSpoof = isHardwareSpoof
    self.emitsXboxGuideReport = emitsXboxGuideReport
    self.evidence = evidence
    self.consumerFamily = consumerFamily
    self.automaticallyRecommended = automaticallyRecommended
    self.evidenceByConsumer = evidenceByConsumer
  }
}

public enum CompatibilityEvidenceStatus: String, Codable, Sendable {
  case sourceBacked
  case hardwareVerified
  case reportedFailure
  case researchOnly
  case unavailable
}

public enum CompatibilityConsumerFamily: String, Codable, Sendable {
  case genericHID
  case sdlHIDAPI
  case appleGameController
  case chromiumGamepad
  case webkitGamepad
  case geckoGamepad
  case xbox360HID
  case unknown
}

/// Official wire families. Krypton vs Argon is XUSB transport, not a backend.
public enum PhysicalProtocolSubfamily: String, Codable, CaseIterable, Sendable {
  case xid
  case xusb
  case gip
  case hid
}

/// Why a compatibility identity is unavailable for a physical protocol family.
public enum CompatibilityProfileAvailabilityReason: String, Codable, Sendable {
  case automaticRequiresResolution
  case xusbIdentityRequiresXUSBFamily
}

/// The result of the pure physical-family and explicit-identity compatibility policy.
public enum CompatibilityProfileAvailabilityDecision: Equatable, Sendable {
  case available
  case unavailable(reason: CompatibilityProfileAvailabilityReason)

  /// Whether the explicit identity is available for this physical family.
  public var isAvailable: Bool {
    if case .available = self { return true }
    return false
  }

  /// The policy reason when the identity is unavailable.
  public var reason: CompatibilityProfileAvailabilityReason? {
    if case .unavailable(let reason) = self { return reason }
    return nil
  }
}

/// Pure Kit-owned policy for physical-family to explicit virtual-identity compatibility.
public enum CompatibilityProfileAvailabilityPolicy {
  /// Evaluates one explicit identity for a connected physical device.
  public static func decision(
    for device: ApplicationServiceDeviceDescription,
    identity: CompatibilityIdentity
  ) -> CompatibilityProfileAvailabilityDecision {
    return decision(for: AutomaticCompatibilityResolver.subfamily(for: device), identity: identity)
  }

  /// Evaluates one explicit identity against one physical protocol subfamily.
  public static func decision(
    for subfamily: PhysicalProtocolSubfamily,
    identity: CompatibilityIdentity
  ) -> CompatibilityProfileAvailabilityDecision {
    switch identity {
    case .automatic: return .unavailable(reason: .automaticRequiresResolution)
    case .genericHID: return .available
    case .xbox360HID:
      return subfamily == .xusb
        ? .available : .unavailable(reason: .xusbIdentityRequiresXUSBFamily)
    case .sdl2_3, .appleGameController, .dualShock4, .dualSense, .switchPro:
      // Automatic routing stays family-strict. Explicit picker/CLI may publish
      // a first-party packer identity so live consumer-bind can be collected.
      return .available
    }
  }


}

public enum AutomaticCompatibilityDecisionReason: String, Codable, Sendable {
  case selectedCatalogTuple
  case selectedFamilyIdentity
  case selectedExplicitIdentity
  case reportedConsumerFailure
  case noAdjacentIdentity
  case unknownConsumer
}

public struct AutomaticCompatibilityResolution: Equatable, Sendable {
  public let identity: CompatibilityIdentity
  public let subfamily: PhysicalProtocolSubfamily
  public let consumer: CompatibilityConsumerFamily
  public let evidence: CompatibilityEvidenceStatus
  public let reason: AutomaticCompatibilityDecisionReason
}

public struct CompatibilityEvidenceRecord: Equatable, Sendable {
  public let vendorID: UInt16?
  public let productID: UInt16?
  public let subfamily: PhysicalProtocolSubfamily
  public let physicalTransport: String
  public let physicalMode: String
  public let connection: String
  public let consumer: CompatibilityConsumerFamily
  public let identity: CompatibilityIdentity
  public let evidence: CompatibilityEvidenceStatus
  public let reason: AutomaticCompatibilityDecisionReason
}

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
    )
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
      let explicit = route.containsExplicit(
        vendorID: device.vendorID,
        productID: device.productID
      )
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
  public static func subfamily(for device: ApplicationServiceDeviceDescription)
    -> PhysicalProtocolSubfamily
  {
    switch device.protocolVariant {
    case .xid: return .xid
    case .xbox360, .xbox360Wireless: return .xusb
    case .xboxOne, .xboxAdaptiveJoystick: return .gip
    case .dualShock3, .dualShock4, .dualSense, .switchPro, .steamController, .flydigi, .genericHID,
      .unknown:
      return .hid
    }
  }

  public static func resolve(
    for device: ApplicationServiceDeviceDescription,
    consumer: CompatibilityConsumerFamily
  ) -> AutomaticCompatibilityResolution {
    CompatibilityEvidenceCatalog.resolution(for: device, consumer: consumer)
  }

  public static func resolve(for device: ApplicationServiceDeviceDescription)
    -> AutomaticCompatibilityResolution
  { resolve(for: device, consumer: .unknown) }
}

public enum CompatibilityOutputProfileCatalog {
  public static func profile(for identity: CompatibilityIdentity) -> CompatibilityOutputProfile {
    switch identity {
    case .automatic: return profile(for: .genericHID)
    case .genericHID:
      return CompatibilityOutputProfile(
        identity: identity,
        deviceProfile: .openJoystickDriverGenericHID,
        displayName: "Generic HID",
        notes: "OJD-owned HID GamePad identity for descriptor-driven consumers.",
        isHardwareSpoof: false,
        emitsXboxGuideReport: false,
        consumerFamily: .genericHID,
        evidenceByConsumer: [.genericHID: .sourceBacked]
      )
    case .sdl2_3:
      return CompatibilityOutputProfile(
        identity: identity,
        deviceProfile: .xbox360Wired,
        displayName: "SDL 2/3",
        notes: "SDL HIDAPI first-party identity for the physical protocol. XUSB "
          + "pads publish Microsoft 045E:028E. Other families use the protocol catalog.",
        isHardwareSpoof: true,
        emitsXboxGuideReport: false,
        evidence: .sourceBacked,
        consumerFamily: .sdlHIDAPI,
        automaticallyRecommended: true,
        evidenceByConsumer: [.sdlHIDAPI: .sourceBacked]
      )
    case .appleGameController:
      return CompatibilityOutputProfile(
        identity: identity,
        deviceProfile: .xboxSeries,
        displayName: "Apple GameController",
        notes: "Apple GameController profile using the Xbox Series Bluetooth layout. "
          + "macOS controller gestures can delay View or reserve Guide and Share unless the "
          + "client disables those gestures.",
        isHardwareSpoof: true,
        emitsXboxGuideReport: false,
        evidence: .sourceBacked,
        consumerFamily: .appleGameController,
        evidenceByConsumer: [
          .appleGameController: .sourceBacked, .chromiumGamepad: .reportedFailure
        ]
      )
    case .xbox360HID:
      return CompatibilityOutputProfile(
        identity: identity,
        deviceProfile: .xbox360Wired,
        displayName: "Xbox 360 HID",
        notes: "Xbox 360-family generic-HID compatibility profile; not Windows XUSB22.sys.",
        isHardwareSpoof: true,
        emitsXboxGuideReport: false,
        evidence: .researchOnly,
        consumerFamily: .xbox360HID,
        evidenceByConsumer: [.xbox360HID: .researchOnly]
      )
    case .dualShock4:
      return CompatibilityOutputProfile(
        identity: identity,
        deviceProfile: .dualShock4USB,
        displayName: "DualShock 4",
        notes: "Sony DualShock 4 USB 054C:09CC. Custom SDL HIDAPI PS4 and "
          + "GCController.supportsHIDDevice bound this identity from an explicit "
          + "GIP picker publish. Automatic for DualShock 4 physical devices.",
        isHardwareSpoof: true,
        emitsXboxGuideReport: false,
        evidence: .sourceBacked,
        consumerFamily: .sdlHIDAPI,
        evidenceByConsumer: [
          .sdlHIDAPI: .sourceBacked, .appleGameController: .sourceBacked,
        ]
      )
    case .dualSense:
      return CompatibilityOutputProfile(
        identity: identity,
        deviceProfile: .dualSenseUSB,
        displayName: "DualSense",
        notes: "Sony DualSense USB 054C:0CE6. Custom SDL HIDAPI PS5 and "
          + "GCController.supportsHIDDevice bound this identity from an explicit "
          + "GIP picker publish. Automatic for DualSense physical devices.",
        isHardwareSpoof: true,
        emitsXboxGuideReport: false,
        evidence: .sourceBacked,
        consumerFamily: .sdlHIDAPI,
        evidenceByConsumer: [
          .sdlHIDAPI: .sourceBacked, .appleGameController: .sourceBacked,
        ]
      )
    case .switchPro:
      return CompatibilityOutputProfile(
        identity: identity,
        deviceProfile: .switchProUSB,
        displayName: "Switch Pro",
        notes: "Nintendo Switch Pro USB 057E:2009. Explicit GIP picker published "
          + "Pro Controller; GCController.supportsHIDDevice bound and custom "
          + "HIDAPI SDL_OpenGamepad opened switchpro. Automatic for Switch Pro "
          + "physical devices.",
        isHardwareSpoof: true,
        emitsXboxGuideReport: false,
        evidence: .sourceBacked,
        consumerFamily: .sdlHIDAPI,
        evidenceByConsumer: [
          .sdlHIDAPI: .sourceBacked, .appleGameController: .sourceBacked,
        ]
      )
    }
  }

}

public struct CompatibilityOutputComposition: Sendable {
  public let profile: CompatibilityOutputProfile
  public let format: any VirtualGamepadReportFormat

  public init(profile: CompatibilityOutputProfile, format: any VirtualGamepadReportFormat) {
    self.profile = profile
    self.format = format
  }
}

public enum CompatibilityOutputCompositionFactory {
  public static func make(identity: CompatibilityIdentity) throws -> CompatibilityOutputComposition
  {
    let profile = CompatibilityOutputProfileCatalog.profile(for: identity)
    let format: any VirtualGamepadReportFormat
    switch identity {
    case .automatic: format = OJDSDLGamepadFormat()
    case .genericHID: format = OJDSDLGamepadFormat()
    case .sdl2_3: format = Xbox360MacHIDReportFormat()
    case .appleGameController:
      format = try HIDDescriptorReportFormat(
        descriptor: XboxOneBluetoothHIDDescriptor.seriesDescriptor,
        outputReportID: VirtualRumbleOutputReportParser.xboxOneReportID,
        outputReportPayloadSize: VirtualRumbleOutputReportParser.xboxOneReportPayloadSize,
        buttonUsageMap: XboxOneBluetoothHIDDescriptor.buttonUsageMap,
        digitalUsageMap: XboxOneBluetoothHIDDescriptor.seriesDigitalUsageMap
      )
    case .xbox360HID: format = Xbox360MacHIDReportFormat(topLevelUsage: 0x05)
    case .dualShock4: format = DualShock4USBHIDReportFormat()
    case .dualSense: format = DualSenseUSBHIDReportFormat()
    case .switchPro: format = SwitchProUSBHIDReportFormat()
    }
    return CompatibilityOutputComposition(profile: profile, format: format)
  }
}
