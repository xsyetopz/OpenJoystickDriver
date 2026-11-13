import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

extension VirtualOutputTests {
  @Test
  func aUnitOverrideRetargetsOnlyThatUnitAndResettingItFallsBackToTheModel() async throws {
    let first = LogicalControllerID(vendorID: 1, productID: 2, locationID: 1)
    let second = LogicalControllerID(vendorID: 1, productID: 2, locationID: 2)
    let fixture = await profileOverrideServer([first, second])
    let automatic = fixture.server.automaticUserSpaceDispatcher()
    func live(_ identifier: LogicalControllerID) -> VirtualHIDProfileID? {
      automatic?.profileState(for: identifier).selection?.profileID
    }

    let set = await fixture.change(
      .set("Generic"),
      controller: .port(try #require(first.testPortKey)),
      unit: true
    )

    #expect(set.failure == nil)
    #expect(live(first) == .generic)
    #expect(live(second) == .sdlCompatible)
    #expect(fixture.store.override(vendorID: 1, productID: 2) == nil)
    #expect(
      fixture.store.override(vendorID: 1, productID: 2, unit: first.testPortKey?.rawValue)
        == .generic
    )

    let reset = await fixture.change(
      .reset,
      controller: .port(try #require(first.testPortKey)),
      unit: true
    )

    #expect(reset.failure == nil)
    #expect(live(first) == .sdlCompatible)
    #expect(fixture.store.files.isEmpty)
    await fixture.tearDown()
  }

  @Test
  func unitOverrideForControllerWithoutUnitIDNotFound() async {
    let fixture = await profileOverrideServer()

    let result = await fixture.change(.set("Generic"), unit: true)

    #expect(result.failure == .controllerNotFound)
    #expect(fixture.store.files.isEmpty)
    await fixture.tearDown()
  }
}
