import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ForegroundConsumerCompatibilityDispatcherPoolTests {
  @Test
  func testEnsuringConsumerRouteDoesNotPublishSecondVirtualController() async throws {
    let bundleRoot = "/Applications/Steam.app"
    let shared = RecordingCompatibilityDispatcher(
      routeToken: UserSpaceVirtualDeviceConstants.sharedRouteToken
    )
    let dedicatedByRoute = LockedRouteDispatchers()

    let pool = try ForegroundConsumerCompatibilityDispatcherPool { requestedRouteToken in
      if let requestedRouteToken {
        return dedicatedByRoute.dispatcher(for: requestedRouteToken)
      }
      return shared
    }

    try await pool.ensureDedicatedRoute(forConsumerBundleRootPath: bundleRoot)

    #expect(dedicatedByRoute.createdRouteTokens.isEmpty)
  }

  @Test
  func testActivatingNeutralConsumerRouteUsesSharedVirtualController() async throws {
    let identifier = DeviceIdentifier(vendorID: 0x1234, productID: 0x5678)
    let bundleRoot = "/Applications/ConsumerA.app"
    let routeToken = UserSpaceVirtualDeviceConstants.dedicatedRouteToken(
      forConsumerBundleRootPath: bundleRoot
    )

    let shared = RecordingCompatibilityDispatcher(
      routeToken: UserSpaceVirtualDeviceConstants.sharedRouteToken
    )
    let dedicatedByRoute = LockedRouteDispatchers()

    let pool = try ForegroundConsumerCompatibilityDispatcherPool { requestedRouteToken in
      if let requestedRouteToken {
        return dedicatedByRoute.dispatcher(for: requestedRouteToken)
      }
      return shared
    }

    await pool.dispatch(events: [], from: identifier)
    try await pool.ensureDedicatedRoute(forConsumerBundleRootPath: bundleRoot)
    await pool.setActiveRouteToken(routeToken)

    #expect(dedicatedByRoute.createdRouteTokens.isEmpty)
    #expect(shared.recordedDispatches.map(\.events) == [[], []])
  }

  @Test
  func testDispatchesInputToSharedControllerWhenNoActiveRouteIsDetected() async throws {
    let identifier = DeviceIdentifier(vendorID: 0x1234, productID: 0x5678)
    let shared = RecordingCompatibilityDispatcher(
      routeToken: UserSpaceVirtualDeviceConstants.sharedRouteToken
    )
    let pool = try ForegroundConsumerCompatibilityDispatcherPool { requestedRouteToken in
      #expect(requestedRouteToken == nil)
      return shared
    }

    await pool.dispatch(events: [.buttonPressed(.a)], from: identifier)

    #expect(shared.recordedDispatches.map(\.events) == [[.buttonPressed(.a)]])
  }

  @Test
  func testStatusPreservesSharedDispatcherTelemetry() throws {
    let shared = RecordingCompatibilityDispatcher(
      routeToken: UserSpaceVirtualDeviceConstants.sharedRouteToken
    )
    shared.status =
      "on (devices=1, dispatches=2, nonEmpty=1, events=1, writes=2, getReports=3)"
    let pool = try ForegroundConsumerCompatibilityDispatcherPool { requestedRouteToken in
      #expect(requestedRouteToken == nil)
      return shared
    }

    let expectedStatus = "on (routes=1, active=none, child=on "
      + "(devices=1, dispatches=2, nonEmpty=1, events=1, writes=2, getReports=3))"
    #expect(pool.status == expectedStatus)
  }

  @Test
  func testClearingActiveRouteNeutralizesSharedButtonState() async throws {
    let identifier = DeviceIdentifier(vendorID: 0x1234, productID: 0x5678)
    let firstBundleRoot = "/Applications/ConsumerA.app"
    let firstRoute = UserSpaceVirtualDeviceConstants.dedicatedRouteToken(
      forConsumerBundleRootPath: firstBundleRoot
    )

    let shared = RecordingCompatibilityDispatcher(
      routeToken: UserSpaceVirtualDeviceConstants.sharedRouteToken
    )
    let dedicatedByRoute = LockedRouteDispatchers()
    let pool = try ForegroundConsumerCompatibilityDispatcherPool { requestedRouteToken in
      if let requestedRouteToken {
        return dedicatedByRoute.dispatcher(for: requestedRouteToken)
      }
      return shared
    }

    try await pool.ensureDedicatedRoute(forConsumerBundleRootPath: firstBundleRoot)
    await pool.setActiveRouteToken(firstRoute)
    await pool.dispatch(events: [.buttonPressed(.a)], from: identifier)
    await pool.setActiveRouteToken(nil)

    #expect(dedicatedByRoute.createdRouteTokens.isEmpty)
    #expect(shared.recordedDispatches.map(\.events).contains([.buttonPressed(.a)]))
    #expect(shared.recordedDispatches.map(\.events).contains([.buttonReleased(.a)]))
  }

  @Test
  func testClearingActiveRouteNeutralizesSharedDpadState() async throws {
    let identifier = DeviceIdentifier(vendorID: 0x1234, productID: 0x5678)
    let firstBundleRoot = "/Applications/ConsumerA.app"
    let firstRoute = UserSpaceVirtualDeviceConstants.dedicatedRouteToken(
      forConsumerBundleRootPath: firstBundleRoot
    )

    let shared = RecordingCompatibilityDispatcher(
      routeToken: UserSpaceVirtualDeviceConstants.sharedRouteToken
    )
    let dedicatedByRoute = LockedRouteDispatchers()
    let pool = try ForegroundConsumerCompatibilityDispatcherPool { requestedRouteToken in
      if let requestedRouteToken {
        return dedicatedByRoute.dispatcher(for: requestedRouteToken)
      }
      return shared
    }

    try await pool.ensureDedicatedRoute(forConsumerBundleRootPath: firstBundleRoot)
    await pool.setActiveRouteToken(firstRoute)
    await pool.dispatch(events: [.dpadChanged(.north)], from: identifier)
    await pool.setActiveRouteToken(nil)

    #expect(dedicatedByRoute.createdRouteTokens.isEmpty)
    #expect(shared.recordedDispatches.map(\.events).contains([.dpadChanged(.north)]))
    #expect(shared.recordedDispatches.map(\.events).contains([.dpadChanged(.neutral)]))
  }
}

private final class LockedRouteDispatchers: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [String: RecordingCompatibilityDispatcher] = [:]

  func dispatcher(for routeToken: String) -> RecordingCompatibilityDispatcher {
    lock.withLock {
      if let existing = storage[routeToken] { return existing }
      let dispatcher = RecordingCompatibilityDispatcher(routeToken: routeToken)
      storage[routeToken] = dispatcher
      return dispatcher
    }
  }

  func dispatcherIfPresent(for routeToken: String) -> RecordingCompatibilityDispatcher? {
    lock.withLock { storage[routeToken] }
  }

  var createdRouteTokens: [String] {
    lock.withLock { storage.keys.sorted() }
  }
}

private final class RecordingCompatibilityDispatcher:
  CompatibilityUserSpaceOutputDispatching, @unchecked Sendable
{
  struct RecordedDispatch: Sendable, Equatable {
    let identifier: DeviceIdentifier
    let events: [ControllerEvent]
  }

  let routeToken: String
  var suppressOutput = false
  var status = "on"
  var lastRumbleStatus = "none"
  private(set) var recordedDispatches: [RecordedDispatch] = []

  init(routeToken: String) {
    self.routeToken = routeToken
  }

  func close() {}

  // swiftlint:disable:next async_without_await
  func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {
    recordedDispatches.append(.init(identifier: identifier, events: events))
  }
}
