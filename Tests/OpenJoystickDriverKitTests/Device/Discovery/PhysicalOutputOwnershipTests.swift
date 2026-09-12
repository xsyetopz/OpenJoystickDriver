import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct PhysicalOutputOwnershipTests {
  @Test func newestMappingClaimWinsAndReleasingItRestoresPreviousClaim() {
    var ownership = PhysicalOutputOwnership()
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 3)
    let first = UUID()
    let second = UUID()
    let channel = PhysicalOutputChannel.rumble(.leftMain)

    ownership.setMapping(
      .rumble(motor: .leftMain, intensity: 0.25), active: true, owner: first, for: identifier
    )
    ownership.setMapping(
      .rumble(motor: .leftMain, intensity: 0.75), active: true, owner: second, for: identifier
    )
    #expect(
      ownership.effectiveOutput(for: channel, device: identifier)
        == .rumble(motor: .leftMain, intensity: 0.75)
    )

    ownership.setMapping(
      .rumble(motor: .leftMain, intensity: 0.75), active: false, owner: second, for: identifier
    )
    #expect(
      ownership.effectiveOutput(for: channel, device: identifier)
        == .rumble(motor: .leftMain, intensity: 0.25)
    )
  }

  @Test func manualOverrideHasPriorityUntilItsNeutralValueReleasesIt() {
    var ownership = PhysicalOutputOwnership()
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 3)
    let channel = PhysicalOutputChannel.playerIndicator

    ownership.setMapping(
      .playerIndicator(.player2), active: true, owner: UUID(), for: identifier
    )
    ownership.setManual(.playerIndicator(.player4), for: identifier)
    #expect(
      ownership.effectiveOutput(for: channel, device: identifier) == .playerIndicator(.player4)
    )

    ownership.setManual(.playerIndicator(.off), for: identifier)
    #expect(
      ownership.effectiveOutput(for: channel, device: identifier) == .playerIndicator(.player2)
    )
  }

  @Test func deviceCleanupCannotAffectAReplacementIdentifier() {
    var ownership = PhysicalOutputOwnership()
    let stale = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 3)
    let replacement = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 4)
    let channel = PhysicalOutputChannel.color

    ownership.setMapping(
      .color(red: 1, green: 2, blue: 3), active: true, owner: UUID(), for: stale
    )
    ownership.setMapping(
      .color(red: 4, green: 5, blue: 6), active: true, owner: UUID(), for: replacement
    )
    ownership.removeDevice(stale)

    #expect(ownership.effectiveOutput(for: channel, device: stale) == nil)
    #expect(
      ownership.effectiveOutput(for: channel, device: replacement)
        == .color(red: 4, green: 5, blue: 6)
    )
  }
}
