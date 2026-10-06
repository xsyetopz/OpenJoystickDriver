import Testing

@testable import OpenJoystickDriverKit

struct ControllerExposureDecisionTests {
  @Test
  func ownedRawUSBInputPublishesGenericByDefault() {
    for ownership in [ControllerOwnershipObservation.exclusiveRawUSB, .driverKitOwnedUSB] {
      let decision = ControllerExposureDecision.decide(
        ownership: ownership,
        intent: .profile(.generic)
      )

      #expect(decision.eligibility == .eligible)
      #expect(decision.duplicateRisk == .none)
    }
  }

  @Test
  func automaticNativeHIDUsesPassThroughAndReportsDuplicateRisk() {
    let decision = ControllerExposureDecision.decide(
      ownership: .nativeHIDVisible,
      intent: .profile(.generic)
    )

    #expect(decision.eligibility == .suppressedNativeHIDPassThrough)
    #expect(decision.duplicateRisk == .nativeHIDVisible)
  }

  @Test
  func seizedHIDInputPublishesTheSelectedProfile() {
    let decision = ControllerExposureDecision.decide(
      ownership: .exclusiveHID,
      intent: .profile(.generic)
    )
    #expect(decision.eligibility == .eligible)
    #expect(decision.duplicateRisk == .none)
  }

  @Test
  func unknownOwnershipPreservesOutputAndReportsUnknownRisk() {
    let decision = ControllerExposureDecision.decide(
      ownership: .unknown,
      intent: .profile(.generic)
    )

    #expect(decision.eligibility == .eligible)
    #expect(decision.duplicateRisk == .unknownOwnership)
  }

  @Test
  func upstreamVirtualSourceIsNotRepublished() {
    let decision = ControllerExposureDecision.decide(
      ownership: .upstreamVirtualDevice,
      intent: .profile(.generic)
    )

    #expect(decision.eligibility == .suppressedUpstreamVirtualDevice)
    #expect(decision.duplicateRisk == .upstreamVirtualDevice)
  }

  @Test
  func disabledOutputSuppressesPublication() {
    let decision = ControllerExposureDecision.decide(
      ownership: .nativeHIDVisible,
      intent: .outputDisabled
    )

    #expect(decision.eligibility == .suppressedOutputDisabled)
  }

  @Test
  func automaticCarriesTheSelectedProfileInsteadOfAnIdentity() {
    let decision = ControllerExposureDecision.decide(
      ownership: .exclusiveRawUSB,
      intent: .profile(.xboxOneSBluetooth)
    )

    #expect(decision.eligibility == .eligible)
    #expect(decision.intent == .profile(.xboxOneSBluetooth))
  }

  @Test
  func decisionIsDeterministicAndNeverSelectsMoreThanOneIdentity() {
    let intent = VirtualOutputIntent.profile(.generic)
    let first = ControllerExposureDecision.decide(ownership: .driverKitOwnedUSB, intent: intent)
    let second = ControllerExposureDecision.decide(ownership: .driverKitOwnedUSB, intent: intent)

    #expect(first == second)
    #expect(first.eligibility == .eligible)
  }
}
