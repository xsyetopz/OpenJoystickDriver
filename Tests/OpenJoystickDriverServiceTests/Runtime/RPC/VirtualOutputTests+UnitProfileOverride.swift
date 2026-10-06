import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

extension VirtualOutputTests {
  @Test
  func aUnitOverrideRetargetsOnlyThatUnitAndResettingItFallsBackToTheModel() async throws {
    let first = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 1)
    let second = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 2)
    let fixture = try await profileOverrideServer([first, second])
    let automatic = fixture.server.automaticUserSpaceDispatcher()
    func live(_ identifier: DeviceIdentifier) -> VirtualHIDProfileID? {
      automatic?.profileState(runtimeIdentifier: identifier.runtimeIdentifier).selection?.profileID
    }

    let set = await fixture.change(
      .set("hid-generic"),
      runtimeIdentifier: first.runtimeIdentifier,
      unit: true
    )

    #expect(set.failure == nil)
    #expect(live(first) == .generic)
    #expect(live(second) == .xboxOneSBluetooth)
    #expect(fixture.store.override(vendorID: 1, productID: 2) == nil)
    #expect(
      fixture.store.override(vendorID: 1, productID: 2, unit: first.unitIdentifier) == .generic
    )

    let reset = await fixture.change(
      .reset,
      runtimeIdentifier: first.runtimeIdentifier,
      unit: true
    )

    #expect(reset.failure == nil)
    #expect(live(first) == .xboxOneSBluetooth)
    #expect(fixture.store.files.isEmpty)
    await fixture.tearDown()
  }

  @Test
  func aUnitOverrideForAControllerWithoutAUnitIDIsNotFound() async throws {
    let fixture = try await profileOverrideServer()

    let result = await fixture.change(.set("hid-generic"), unit: true)

    #expect(result.failure == .controllerNotFound)
    #expect(fixture.store.files.isEmpty)
    await fixture.tearDown()
  }
}
