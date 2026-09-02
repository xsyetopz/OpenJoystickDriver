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
  case xboxOneHID
  case xbox360HID
  case unknown
}

public enum PhysicalProtocolSubfamily: String, Codable, Sendable {
  case xboxOriginal
  case xbox360
  case xboxGIP
  case nintendoSwitchPro
  case nintendoOther
  case playStationDS4
  case playStationDS5
  case playStationOther
  case other

}

public enum AutomaticCompatibilityDecisionReason: String, Codable, Sendable {
  case selectedCatalogTuple
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
      vendorID: 0x045E,
      productID: 0x02FD,
      subfamily: .xboxGIP,
      physicalTransport: "bluetooth",
      physicalMode: "gip",
      connection: "bluetooth",
      consumer: .sdlHIDAPI,
      identity: .genericHID,
      evidence: .reportedFailure,
      reason: .reportedConsumerFailure
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
  static func subfamily(for device: ApplicationServiceDeviceDescription)
    -> PhysicalProtocolSubfamily
  {
    let subfamily: PhysicalProtocolSubfamily
    switch device.protocolVariant {
    case .xboxOriginal: subfamily = .xboxOriginal
    case .xbox360, .xbox360Wireless: subfamily = .xbox360
    case .xboxOne, .xboxAdaptiveJoystick: subfamily = .xboxGIP
    case .dualShock4: subfamily = .playStationDS4
    case .dualSense: subfamily = .playStationDS5
    case .switchPro: subfamily = .nintendoSwitchPro
    case .genericHID, .dualShock3, .steamController, .unknown: subfamily = .other
    }
    return subfamily
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
        deviceProfile: .sdlHIDAPIXbox360,
        displayName: "SDL 2/3",
        notes: "Hardware-verified SDL HIDAPI identity with Xbox 360 input and rumble reports.",
        isHardwareSpoof: true,
        emitsXboxGuideReport: false,
        evidence: .hardwareVerified,
        consumerFamily: .sdlHIDAPI,
        automaticallyRecommended: false,
        evidenceByConsumer: [.sdlHIDAPI: .hardwareVerified]
      )
    case .appleGameController:
      return CompatibilityOutputProfile(
        identity: identity,
        deviceProfile: .xboxOneS,
        displayName: "Apple GameController",
        notes: "Source-backed Apple GameController candidate using the Xbox One S "
          + "Bluetooth HID tuple; live input and haptics remain unverified.",
        isHardwareSpoof: true,
        emitsXboxGuideReport: true,
        evidence: .sourceBacked,
        consumerFamily: .appleGameController,
        evidenceByConsumer: [.appleGameController: .sourceBacked]
      )
    case .xoneHID:
      return CompatibilityOutputProfile(
        identity: identity,
        deviceProfile: .xboxOneS,
        displayName: "Xbox One HID (legacy)",
        notes: "Source-backed Xbox One Bluetooth-shaped generic-HID compatibility tuple; "
          + "not XInputHID, XUSB, or GIP; consumer input and rumble require live testing.",
        isHardwareSpoof: true,
        emitsXboxGuideReport: true,
        evidence: .sourceBacked,
        consumerFamily: .xboxOneHID,
        evidenceByConsumer: [
          .xboxOneHID: .sourceBacked, .sdlHIDAPI: .reportedFailure,
          .appleGameController: .sourceBacked
        ]
      )
    case .xbox360HID:
      return CompatibilityOutputProfile(
        identity: identity,
        deviceProfile: .xbox360Wired,
        displayName: "Xbox 360 HID",
        notes: "Xbox 360-family generic-HID compatibility profile; not Windows XUSB.",
        isHardwareSpoof: true,
        emitsXboxGuideReport: false,
        evidence: .researchOnly,
        consumerFamily: .xbox360HID,
        evidenceByConsumer: [.xbox360HID: .researchOnly]
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
    case .appleGameController, .xoneHID:
      format = try HIDDescriptorReportFormat(
        descriptor: XboxOneBluetoothHIDDescriptor.descriptor,
        outputReportID: VirtualRumbleOutputReportParser.xboxOneReportID,
        outputReportPayloadSize: VirtualRumbleOutputReportParser.xboxOneReportPayloadSize
      )
    case .xbox360HID: format = Xbox360MacHIDReportFormat(topLevelUsage: 0x05)
    }
    return CompatibilityOutputComposition(profile: profile, format: format)
  }
}
