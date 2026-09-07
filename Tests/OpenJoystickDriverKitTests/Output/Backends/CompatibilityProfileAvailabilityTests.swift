import Testing

@testable import OpenJoystickDriverKit

struct CompatibilityProfileAvailabilityTests {
  private let subfamilies: [PhysicalProtocolSubfamily] = [.xid, .xusb, .gip, .hid]
  private let identities: [CompatibilityIdentity] = [
    .automatic, .genericHID, .sdl2_3, .appleGameController, .xbox360HID, .dualShock4, .dualSense,
    .switchPro
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
        case .sdl2_3, .appleGameController, .dualShock4, .dualSense, .switchPro:
          expected = .available
        case .xbox360HID:
          expected =
            subfamily == .xusb
            ? .available : .unavailable(reason: .xusbIdentityRequiresXUSBFamily)
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
      CompatibilityProfileAvailabilityPolicy.decision(for: .gip, identity: .sdl2_3) == .available
    )
    #expect(
      CompatibilityProfileAvailabilityPolicy.decision(for: .gip, identity: .appleGameController)
        == .available
    )
    #expect(
      CompatibilityProfileAvailabilityPolicy.decision(for: .xusb, identity: .sdl2_3)
        == .available
    )
    #expect(CompatibilityProfileAvailabilityPolicy.isAvailable(.sdl2_3, for: .hid) == true)
    #expect(CompatibilityProfileAvailabilityPolicy.isAvailable(.xbox360HID, for: .hid) == false)
    #expect(CompatibilityProfileAvailabilityPolicy.isAvailable(.xbox360HID, for: .gip) == false)
    #expect(CompatibilityProfileAvailabilityPolicy.isAvailable(.dualShock4, for: .hid) == true)
    #expect(CompatibilityProfileAvailabilityPolicy.isAvailable(.switchPro, for: .hid) == true)
    #expect(CompatibilityProfileAvailabilityPolicy.isAvailable(.dualSense, for: .gip) == true)
    #expect(CompatibilityProfileAvailabilityPolicy.isAvailable(.dualShock4, for: .gip) == true)
    #expect(CompatibilityProfileAvailabilityPolicy.isAvailable(.dualShock4, for: .xusb) == true)
  }

  @Test func connectedGIPDeviceAllowsExplicitFirstPartyIdentities() {
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

  @Test func automaticMustBeResolvedBeforePolicyEvaluation() {
    let decision = CompatibilityProfileAvailabilityPolicy.decision(
      for: .xusb,
      identity: .automatic
    )

    #expect(decision == .unavailable(reason: .automaticRequiresResolution))
    #expect(decision.isAvailable == false)
  }
}
