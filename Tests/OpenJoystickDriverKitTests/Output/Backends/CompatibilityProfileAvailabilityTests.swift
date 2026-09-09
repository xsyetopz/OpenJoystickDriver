import Testing

@testable import OpenJoystickDriverKit

struct CompatibilityProfileAvailabilityTests {
  private let subfamilies: [PhysicalProtocolSubfamily] = [.xid, .xusb, .gip, .hid]
  private let identities: [CompatibilityIdentity] = [
    .automatic, .genericHID, .sdl2_3, .appleGameController, .xbox360HID, .dualShock4, .dualSense,
    .switchPro,
  ]

  @Test
  func everyPhysicalFamilyHasTheExpectedIdentityMatrix() {
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
        case .sdl2_3, .appleGameController, .dualShock4, .dualSense, .switchPro:
          expected = .available
        case .xbox360HID:
          expected =
            subfamily == .xusb ? .available : .unavailable(reason: .xusbIdentityRequiresXUSBFamily)
        }
        #expect(decision == expected)

      }
    }
  }

  @Test
  func requestedBoundaryRowsRemainExplicit() {
    #expect(
      CompatibilityProfileAvailabilityPolicy.decision(for: .gip, identity: .sdl2_3) == .available
    )
    #expect(
      CompatibilityProfileAvailabilityPolicy.decision(for: .gip, identity: .appleGameController)
        == .available
    )
    #expect(
      CompatibilityProfileAvailabilityPolicy.decision(for: .xusb, identity: .sdl2_3) == .available
    )
    #expect(
      CompatibilityProfileAvailabilityPolicy.decision(for: .hid, identity: .sdl2_3).isAvailable
        == true
    )
    #expect(
      CompatibilityProfileAvailabilityPolicy.decision(for: .hid, identity: .xbox360HID).isAvailable
        == false
    )
    #expect(
      CompatibilityProfileAvailabilityPolicy.decision(for: .gip, identity: .xbox360HID).isAvailable
        == false
    )
    #expect(
      CompatibilityProfileAvailabilityPolicy.decision(for: .hid, identity: .dualShock4).isAvailable
        == true
    )
    #expect(
      CompatibilityProfileAvailabilityPolicy.decision(for: .hid, identity: .switchPro).isAvailable
        == true
    )
    #expect(
      CompatibilityProfileAvailabilityPolicy.decision(for: .gip, identity: .dualSense).isAvailable
        == true
    )
    #expect(
      CompatibilityProfileAvailabilityPolicy.decision(for: .gip, identity: .dualShock4).isAvailable
        == true
    )
    #expect(
      CompatibilityProfileAvailabilityPolicy.decision(for: .xusb, identity: .dualShock4).isAvailable
        == true
    )
  }

  @Test
  func connectedGIPDeviceAllowsExplicitFirstPartyIdentities() {
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
      CompatibilityProfileAvailabilityPolicy.decision(for: device, identity: .sdl2_3) == .available
    )
    #expect(
      CompatibilityProfileAvailabilityPolicy.decision(for: device, identity: .xbox360HID)
        == .unavailable(reason: .xusbIdentityRequiresXUSBFamily)
    )
    #expect(
      CompatibilityProfileAvailabilityPolicy.decision(for: device, identity: .appleGameController)
        == .available
    )
    #expect(
      CompatibilityProfileAvailabilityPolicy.decision(for: device, identity: .dualShock4)
        == .available
    )
  }

  @Test
  func automaticMustBeResolvedBeforePolicyEvaluation() {
    let decision = CompatibilityProfileAvailabilityPolicy.decision(for: .xusb, identity: .automatic)

    #expect(decision == .unavailable(reason: .automaticRequiresResolution))
    #expect(decision.isAvailable == false)
  }
}
