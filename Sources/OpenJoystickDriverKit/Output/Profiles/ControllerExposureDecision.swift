/// How OJD owns or observes the physical controller input path.
public enum ControllerOwnershipObservation: String, Codable, Equatable, Sendable {
  case exclusiveRawUSB
  case driverKitOwnedUSB
  case nativeHIDVisible
  case upstreamVirtualDevice
  case unknown
}

/// The non-persisted exposure request used by the policy layer.
///
/// Persisted compatibility identities remain represented by `CompatibilityIdentity` and retain
/// their existing raw values. This type adds exposure policy without changing that contract.
public enum CompatibilityIdentityIntent: Equatable, Sendable {
  case automatic(resolvedIdentity: CompatibilityIdentity)
  case explicit(CompatibilityIdentity)
  case passThrough
  case outputDisabled
}

/// Whether a physical controller is eligible for one OJD virtual publication.
public enum VirtualExposureEligibility: Equatable, Sendable {
  case eligible
  case suppressedUpstreamVirtualDevice
  case suppressedOutputDisabled
  case suppressedUnsupportedIdentity
  case rejectedInvalidIntent
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
  /// The requested compatibility exposure mode.
  public let intent: CompatibilityIdentityIntent
  /// Whether publication is allowed for this request.
  public let eligibility: VirtualExposureEligibility
  /// The concrete identity to publish, when eligible.
  public let effectiveIdentity: CompatibilityIdentity?
  /// The duplicate-device concern associated with the observation.
  public let duplicateRisk: DuplicateExposureRisk

  /// Creates a policy result.
  public init(
    ownership: ControllerOwnershipObservation,
    intent: CompatibilityIdentityIntent,
    eligibility: VirtualExposureEligibility,
    effectiveIdentity: CompatibilityIdentity?,
    duplicateRisk: DuplicateExposureRisk
  ) {
    self.ownership = ownership
    self.intent = intent
    self.eligibility = eligibility
    self.effectiveIdentity = effectiveIdentity
    self.duplicateRisk = duplicateRisk
  }

  /// Resolves exposure without inspecting framework state or publishing a backend.
  public static func decide(
    ownership: ControllerOwnershipObservation,
    intent: CompatibilityIdentityIntent,
    profileAvailable: Bool = true
  ) -> Self {
    let duplicateRisk: DuplicateExposureRisk =
      switch ownership {
      case .exclusiveRawUSB, .driverKitOwnedUSB: .none
      case .nativeHIDVisible: .nativeHIDVisible
      case .upstreamVirtualDevice: .upstreamVirtualDevice
      case .unknown: .unknownOwnership
      }

    switch intent {
    case .passThrough, .outputDisabled:
      return Self(
        ownership: ownership,
        intent: intent,
        eligibility: .suppressedOutputDisabled,
        effectiveIdentity: nil,
        duplicateRisk: duplicateRisk
      )
    case .automatic(let resolvedIdentity):
      guard resolvedIdentity != .automatic else {
        return Self(
          ownership: ownership,
          intent: intent,
          eligibility: .rejectedInvalidIntent,
          effectiveIdentity: nil,
          duplicateRisk: duplicateRisk
        )
      }
    case .explicit(let requested):
      guard requested != .automatic else {
        return Self(
          ownership: ownership,
          intent: intent,
          eligibility: .rejectedInvalidIntent,
          effectiveIdentity: nil,
          duplicateRisk: duplicateRisk
        )
      }
    }

    if ownership == .upstreamVirtualDevice {
      return Self(
        ownership: ownership,
        intent: intent,
        eligibility: .suppressedUpstreamVirtualDevice,
        effectiveIdentity: nil,
        duplicateRisk: duplicateRisk
      )
    }

    guard profileAvailable else {
      return Self(
        ownership: ownership,
        intent: intent,
        eligibility: .suppressedUnsupportedIdentity,
        effectiveIdentity: nil,
        duplicateRisk: duplicateRisk
      )
    }

    let identity: CompatibilityIdentity
    switch intent {
    case .automatic(let resolvedIdentity): identity = resolvedIdentity
    case .explicit(let requested): identity = requested
    case .passThrough, .outputDisabled: fatalError("Unreachable exposure intent")
    }

    return Self(
      ownership: ownership,
      intent: intent,
      eligibility: .eligible,
      effectiveIdentity: identity,
      duplicateRisk: duplicateRisk
    )
  }

}
