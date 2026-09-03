import Testing

@testable import OpenJoystickDriverKit

struct ControllerExposureDecisionTests {
  @Test func ownedPhysicalInputPublishesGenericByDefault() {
    for ownership in [ControllerOwnershipObservation.exclusiveRawUSB, .driverKitOwnedUSB] {
      let decision = ControllerExposureDecision.decide(
        ownership: ownership,
        intent: .automatic(resolvedIdentity: .genericHID)
      )

      #expect(decision.eligibility == .eligible)
      #expect(decision.effectiveIdentity == .genericHID)
      #expect(decision.duplicateRisk == .none)
    }
  }

  @Test func nativeHIDRemainsEligibleAndReportsDuplicateRisk() {
    let decision = ControllerExposureDecision.decide(
      ownership: .nativeHIDVisible,
      intent: .automatic(resolvedIdentity: .genericHID)
    )

    #expect(decision.eligibility == .eligible)
    #expect(decision.effectiveIdentity == .genericHID)
    #expect(decision.duplicateRisk == .nativeHIDVisible)
  }

  @Test func unknownOwnershipPreservesOutputAndReportsUnknownRisk() {
    let decision = ControllerExposureDecision.decide(
      ownership: .unknown,
      intent: .automatic(resolvedIdentity: .genericHID)
    )

    #expect(decision.eligibility == .eligible)
    #expect(decision.effectiveIdentity == .genericHID)
    #expect(decision.duplicateRisk == .unknownOwnership)
  }

  @Test func upstreamVirtualSourceIsNotRepublished() {
    let decision = ControllerExposureDecision.decide(
      ownership: .upstreamVirtualDevice,
      intent: .automatic(resolvedIdentity: .genericHID)
    )

    #expect(decision.eligibility == .suppressedUpstreamVirtualDevice)
    #expect(decision.effectiveIdentity == nil)
    #expect(decision.duplicateRisk == .upstreamVirtualDevice)
  }

  @Test(arguments: [CompatibilityIdentityIntent.passThrough, .outputDisabled])
  func disabledIntentsSuppressEveryOwnership(_ intent: CompatibilityIdentityIntent) {
    let decision = ControllerExposureDecision.decide(ownership: .nativeHIDVisible, intent: intent)

    #expect(decision.eligibility == .suppressedOutputDisabled)
    #expect(decision.effectiveIdentity == nil)
  }

  @Test func explicitIdentityRemainsAtomicAndAutomaticKeepsGenericSemantics() {
    let explicit = ControllerExposureDecision.decide(
      ownership: .exclusiveRawUSB,
      intent: .explicit(.xbox360HID)
    )
    let invalidAutomaticIdentity = ControllerExposureDecision.decide(
      ownership: .exclusiveRawUSB,
      intent: .explicit(.automatic)
    )

    #expect(explicit.eligibility == .eligible)
    #expect(explicit.effectiveIdentity == .xbox360HID)
    #expect(invalidAutomaticIdentity.eligibility == .rejectedInvalidIntent)
    #expect(invalidAutomaticIdentity.effectiveIdentity == nil)
  }

  @Test func automaticUsesResolverOutputWithoutGenericFallback() {
    let decision = ControllerExposureDecision.decide(
      ownership: .exclusiveRawUSB,
      intent: .automatic(resolvedIdentity: .xbox360HID)
    )

    #expect(decision.eligibility == .eligible)
    #expect(decision.effectiveIdentity == .xbox360HID)
  }

  @Test func unavailableProfileSuppressesPublication() {
    let decision = ControllerExposureDecision.decide(
      ownership: .exclusiveRawUSB,
      intent: .explicit(.genericHID),
      profileAvailable: false
    )

    #expect(decision.eligibility == .suppressedUnsupportedIdentity)
    #expect(decision.effectiveIdentity == nil)
  }

  @Test func decisionIsDeterministicAndNeverSelectsMoreThanOneIdentity() {
    let intent = CompatibilityIdentityIntent.automatic(resolvedIdentity: .genericHID)
    let first = ControllerExposureDecision.decide(ownership: .driverKitOwnedUSB, intent: intent)
    let second = ControllerExposureDecision.decide(ownership: .driverKitOwnedUSB, intent: intent)

    #expect(first == second)
    #expect(first.effectiveIdentity == .genericHID)
  }
}
