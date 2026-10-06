/// How OJD owns or observes the physical controller input path.
public enum ControllerOwnershipObservation: String, Codable, Equatable, Sendable {
  case exclusiveHID
  case exclusiveRawUSB
  case driverKitOwnedUSB
  case nativeHIDVisible
  /// macOS serves the controller as a native gamepad; OJD only observes its shared input.
  case nativeGamepad
  case upstreamVirtualDevice
  case unknown
}

/// The non-persisted virtual output request used by the policy layer.
public enum VirtualOutputIntent: Equatable, Sendable {
  /// Publication of the profile `VirtualHIDProfileSelector` chose.
  case profile(VirtualHIDProfileID)
  /// No virtual publication.
  case outputDisabled
}

/// Whether a physical controller is eligible for one OJD virtual publication.
public enum VirtualExposureEligibility: Equatable, Sendable {
  case eligible
  case suppressedUpstreamVirtualDevice
  case suppressedOutputDisabled
  case suppressedNativeHIDPassThrough
}

/// The duplicate-device concern associated with the physical ownership observation.
public enum DuplicateExposureRisk: String, Codable, Equatable, Sendable {
  case none
  case nativeHIDVisible
  case upstreamVirtualDevice
  case unknownOwnership
}

/// Pure policy result for one physical controller and one virtual exposure intent.
public struct ControllerExposureDecision: Equatable, Sendable {
  /// The observed ownership of the physical input path.
  public let ownership: ControllerOwnershipObservation
  /// The requested virtual output.
  public let intent: VirtualOutputIntent
  /// Whether publication is allowed for this request.
  public let eligibility: VirtualExposureEligibility
  /// The duplicate-device concern associated with the observation.
  public let duplicateRisk: DuplicateExposureRisk

  /// Creates a policy result.
  public init(
    ownership: ControllerOwnershipObservation,
    intent: VirtualOutputIntent,
    eligibility: VirtualExposureEligibility,
    duplicateRisk: DuplicateExposureRisk
  ) {
    self.ownership = ownership
    self.intent = intent
    self.eligibility = eligibility
    self.duplicateRisk = duplicateRisk
  }

  /// Resolves exposure without inspecting framework state or publishing a backend.
  public static func decide(
    ownership: ControllerOwnershipObservation,
    intent: VirtualOutputIntent
  ) -> Self {
    let duplicateRisk: DuplicateExposureRisk =
      switch ownership {
      // OJD never publishes for a native gamepad, so games see only Apple's device.
      case .exclusiveHID, .exclusiveRawUSB, .driverKitOwnedUSB, .nativeGamepad: .none
      case .nativeHIDVisible: .nativeHIDVisible
      case .upstreamVirtualDevice: .upstreamVirtualDevice
      case .unknown: .unknownOwnership
      }

    switch intent {
    case .outputDisabled:
      return Self(
        ownership: ownership,
        intent: intent,
        eligibility: .suppressedOutputDisabled,
        duplicateRisk: duplicateRisk
      )
    case .profile:
      if ownership == .nativeHIDVisible {
        return Self(
          ownership: ownership,
          intent: intent,
          eligibility: .suppressedNativeHIDPassThrough,
          duplicateRisk: duplicateRisk
        )
      }
    }

    if ownership == .nativeGamepad {
      return Self(
        ownership: ownership,
        intent: intent,
        eligibility: .suppressedNativeHIDPassThrough,
        duplicateRisk: duplicateRisk
      )
    }

    if ownership == .upstreamVirtualDevice {
      return Self(
        ownership: ownership,
        intent: intent,
        eligibility: .suppressedUpstreamVirtualDevice,
        duplicateRisk: duplicateRisk
      )
    }

    return Self(
      ownership: ownership,
      intent: intent,
      eligibility: .eligible,
      duplicateRisk: duplicateRisk
    )
  }

}
