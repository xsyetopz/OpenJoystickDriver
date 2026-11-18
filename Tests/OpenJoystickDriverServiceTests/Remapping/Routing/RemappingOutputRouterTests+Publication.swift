import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

extension RemappingOutputRouterTests {
  /// The pipeline stamps `DeliveryVirtualDevice` for `ojd diagnose` from this callback.
  @Test
  func virtualGamepadRouteReportsPublishedFrame() async throws {
    let harness = try await RemappingRouterHarness.make()
    defer { harness.removeFiles() }
    let device = remappingRouterDevice(1)
    let published = Locked(0)

    try await harness.router.dispatchPublishing(
      ControllerEvent([.press(.south)]),
      from: device
    ) { published.withLock { $0 += 1 } }

    #expect(published.withLock { $0 } == 1)
    #expect(harness.recorder.snapshot().count == 1)
  }

  @Test
  func suppressedFrameReportsNoPublication() async throws {
    let harness = try await RemappingRouterHarness.make()
    defer { harness.removeFiles() }
    harness.virtualOutput.suppressOutput = true
    let published = Locked(0)

    try await harness.router.dispatchPublishing(
      ControllerEvent([.press(.south)]),
      from: remappingRouterDevice(1)
    ) { published.withLock { $0 += 1 } }

    #expect(published.withLock { $0 } == 0)
  }
}
