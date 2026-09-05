import Testing

@testable import OpenJoystickDriverKit

struct CompatibilityProfileAvailabilityTests {
  private let subfamilies: [PhysicalProtocolSubfamily] = [
    .xboxOriginal, .xbox360, .xboxGIP, .nintendoSwitchPro, .nintendoOther, .playStationDS4,
    .playStationDS5, .playStationOther, .other
  ]
  private let identities: [CompatibilityIdentity] = [
    .automatic, .genericHID, .sdl2_3, .appleGameController, .xbox360HID
  ]

  @Test func everyPhysicalFamilyHasTheExpectedIdentityMatrix() {
    for subfamily in subfamilies {
      for identity in identities {
        let decision = CompatibilityProfileAvailabilityPolicy.decision(
          for: subfamily,
          identity: identity
        )
        let expected: CompatibilityProfileAvailabilityDecision
        switch identity {
        case .automatic: expected = .unavailable(reason: .automaticRequiresResolution)
        case .genericHID: expected = .available
        case .sdl2_3, .xbox360HID:
          expected =
            subfamily == .xbox360
            ? .available : .unavailable(reason: .xbox360IdentityRequiresXbox360Family)
        case .appleGameController:
          expected =
            subfamily == .xboxGIP
            ? .available : .unavailable(reason: .xboxOneIdentityRequiresXboxGIPFamily)
        }
        #expect(decision == expected)
        #expect(
          CompatibilityProfileAvailabilityPolicy.isAvailable(identity, for: subfamily)
            == decision.isAvailable
        )
        #expect(decision.profileAvailable == decision.isAvailable)
      }
    }
  }

  @Test func requestedBoundaryRowsRemainExplicit() {
    #expect(
      CompatibilityProfileAvailabilityPolicy.decision(for: .xboxGIP, identity: .sdl2_3)
        == .unavailable(reason: .xbox360IdentityRequiresXbox360Family)
    )
    #expect(
      CompatibilityProfileAvailabilityPolicy.decision(for: .xboxGIP, identity: .appleGameController)
        == .available
    )
    #expect(
      CompatibilityProfileAvailabilityPolicy.decision(for: .xbox360, identity: .sdl2_3)
        == .available
    )
    for subfamily in [
      PhysicalProtocolSubfamily.nintendoSwitchPro, .nintendoOther, .playStationDS4, .playStationDS5,
      .playStationOther
    ] {
      #expect(CompatibilityProfileAvailabilityPolicy.isAvailable(.sdl2_3, for: subfamily) == false)
      #expect(
        CompatibilityProfileAvailabilityPolicy.isAvailable(.xbox360HID, for: subfamily) == false
      )
    }
  }

  @Test func connectedGIPDeviceRejectsXbox360FamilyIdentities() {
    let device = ApplicationServiceDeviceDescription(
      name: "GIP",
      vendorID: 1,
      productID: 2,
      parser: "GIP",
      connection: "USB",
      serialNumber: nil,
      protocolVariant: .xboxOne
    )

    #expect(
      CompatibilityProfileAvailabilityPolicy.decision(for: device, identity: .sdl2_3)
        == .unavailable(reason: .xbox360IdentityRequiresXbox360Family)
    )
    #expect(
      CompatibilityProfileAvailabilityPolicy.decision(for: device, identity: .xbox360HID)
        == .unavailable(reason: .xbox360IdentityRequiresXbox360Family)
    )
    #expect(
      CompatibilityProfileAvailabilityPolicy.decision(for: device, identity: .appleGameController)
        == .available
    )
  }

  @Test func automaticMustBeResolvedBeforePolicyEvaluation() {
    let decision = CompatibilityProfileAvailabilityPolicy.decision(
      for: .xbox360,
      identity: .automatic
    )

    #expect(decision == .unavailable(reason: .automaticRequiresResolution))
    #expect(decision.isAvailable == false)
  }
}
