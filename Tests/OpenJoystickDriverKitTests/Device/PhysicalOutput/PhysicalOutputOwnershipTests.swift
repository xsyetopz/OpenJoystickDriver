import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct PhysicalOutputOwnershipTests {
  @Test
  func newestMappingClaimWinsAndReleasingItRestoresPreviousClaim() {
    var ownership = PhysicalOutputOwnership()
    let identifier = LogicalControllerID(vendorID: 1, productID: 2, locationID: 3)
    let first = UUID()
    let second = UUID()
    let channel = PhysicalOutputChannel.rumble(.lowFrequency)

    ownership.setMapping(
      .rumble(motor: .lowFrequency, intensity: 0.25),
      active: true,
      owner: first,
      for: identifier
    )
    ownership.setMapping(
      .rumble(motor: .lowFrequency, intensity: 0.75),
      active: true,
      owner: second,
      for: identifier
    )
    #expect(
      ownership.effectiveOutput(for: channel, device: identifier)
        == .rumble(motor: .lowFrequency, intensity: 0.75)
    )

    ownership.setMapping(
      .rumble(motor: .lowFrequency, intensity: 0.75),
      active: false,
      owner: second,
      for: identifier
    )
    #expect(
      ownership.effectiveOutput(for: channel, device: identifier)
        == .rumble(motor: .lowFrequency, intensity: 0.25)
    )
  }

  @Test
  func manualOverrideHasPriorityUntilItsNeutralValueReleasesIt() {
    var ownership = PhysicalOutputOwnership()
    let identifier = LogicalControllerID(vendorID: 1, productID: 2, locationID: 3)
    let channel = PhysicalOutputChannel.playerIndicator

    ownership.setMapping(.playerIndicator(.player2), active: true, owner: UUID(), for: identifier)
    ownership.setManual(.playerIndicator(.player4), for: identifier)
    #expect(
      ownership.effectiveOutput(for: channel, device: identifier) == .playerIndicator(.player4)
    )

    ownership.setManual(.playerIndicator(.off), for: identifier)
    #expect(
      ownership.effectiveOutput(for: channel, device: identifier) == .playerIndicator(.player2)
    )
  }

  @Test
  func deviceCleanupCannotAffectReplacementIdentifier() {
    var ownership = PhysicalOutputOwnership()
    let stale = LogicalControllerID(vendorID: 1, productID: 2, locationID: 3)
    let replacement = LogicalControllerID(vendorID: 1, productID: 2, locationID: 4)
    let channel = PhysicalOutputChannel.color

    ownership.setMapping(
      .color(ControllerColor(red: 1, green: 2, blue: 3)),
      active: true,
      owner: UUID(),
      for: stale
    )
    ownership.setMapping(
      .color(ControllerColor(red: 4, green: 5, blue: 6)),
      active: true,
      owner: UUID(),
      for: replacement
    )
    ownership.removeDevice(stale)

    #expect(ownership.effectiveOutput(for: channel, device: stale) == nil)
    #expect(
      ownership.effectiveOutput(for: channel, device: replacement)
        == .color(ControllerColor(red: 4, green: 5, blue: 6))
    )
  }

  @Test
  func colorPrecedenceRestoresMappingThenProfileAndTreatsBlackAsSelected() {
    var ownership = PhysicalOutputOwnership()
    let identifier = LogicalControllerID(vendorID: 1, productID: 2, locationID: 3)
    let mappingOwner = UUID()
    let previewToken = UUID()

    ownership.setProfileColor(.color(ControllerColor(red: 1, green: 2, blue: 3)), for: identifier)
    ownership.setMapping(
      .color(ControllerColor(red: 4, green: 5, blue: 6)),
      active: true,
      owner: mappingOwner,
      for: identifier
    )
    ownership.setTemporaryColor(
      .color(ControllerColor(red: 0, green: 0, blue: 0)),
      token: previewToken,
      for: identifier
    )
    #expect(
      ownership.effectiveOutput(for: .color, device: identifier)
        == .color(ControllerColor(red: 0, green: 0, blue: 0))
    )

    ownership.releaseTemporaryColor(token: previewToken, for: identifier)
    #expect(
      ownership.effectiveOutput(for: .color, device: identifier)
        == .color(ControllerColor(red: 4, green: 5, blue: 6))
    )

    ownership.setMapping(
      .color(ControllerColor(red: 4, green: 5, blue: 6)),
      active: false,
      owner: mappingOwner,
      for: identifier
    )
    #expect(
      ownership.effectiveOutput(for: .color, device: identifier)
        == .color(ControllerColor(red: 1, green: 2, blue: 3))
    )
  }

  @Test
  func rollingBackOneChannelKeepsOtherChannelsAndControllers() {
    var ownership = PhysicalOutputOwnership()
    let first = LogicalControllerID(vendorID: 1, productID: 2, locationID: 3)
    let second = LogicalControllerID(vendorID: 1, productID: 2, locationID: 4)
    let rumble = PhysicalOutputChannel.rumble(.lowFrequency)
    let colorBefore = ownership.state(of: [.color], for: first)

    ownership.setTemporaryColor(
      .color(ControllerColor(red: 1, green: 2, blue: 3)),
      token: UUID(),
      for: first
    )
    _ = ownership.setManual(.rumble(motor: .lowFrequency, intensity: 1), for: first)
    _ = ownership.setManual(.rumble(motor: .lowFrequency, intensity: 0.5), for: second)
    ownership.restore(colorBefore)

    #expect(ownership.effectiveOutput(for: .color, device: first) == nil)
    #expect(
      ownership.effectiveOutput(for: rumble, device: first)
        == .rumble(motor: .lowFrequency, intensity: 1)
    )
    #expect(
      ownership.effectiveOutput(for: rumble, device: second)
        == .rumble(motor: .lowFrequency, intensity: 0.5)
    )
  }

  /// A rollback captured before the controller's claims were cleared must not bring them back.
  @Test
  func rollbackCapturedBeforeClearingRestoresNothing() {
    var ownership = PhysicalOutputOwnership()
    let identifier = LogicalControllerID(vendorID: 1, productID: 2, locationID: 3)
    ownership.setMapping(.playerIndicator(.player1), active: true, owner: UUID(), for: identifier)
    let beforeDevice = ownership.state(of: [.playerIndicator], for: identifier)
    ownership.removeDevice(identifier)
    ownership.restore(beforeDevice)
    #expect(ownership.effectiveOutput(for: .playerIndicator, device: identifier) == nil)

    ownership.setMapping(.playerIndicator(.player2), active: true, owner: UUID(), for: identifier)
    let beforeAll = ownership.state(of: [.playerIndicator], for: identifier)
    ownership.removeAll()
    ownership.restore(beforeAll)
    #expect(ownership.effectiveOutput(for: .playerIndicator, device: identifier) == nil)
  }
}
