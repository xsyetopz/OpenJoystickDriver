import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ForegroundConsumerCompatibilityDispatcherPoolTests {
  @Test func testNeutralSelfTestDispatchReachesFallbackWithoutActiveConsumer() async throws {
    let identifier = DeviceIdentifier(vendorID: 0x4F4A, productID: 0x5445)
    let shared = RecordingCompatibilityDispatcher(routeToken: "shared")
    let pool = try makePool(shared: shared, dedicatedByRoute: LockedRouteDispatchers())

    await pool.dispatch(events: [.buttonPressed(.a)], from: identifier)
    #expect(shared.recordedDispatches.isEmpty)

    await pool.dispatch(events: [], from: identifier)

    #expect(shared.recordedDispatches == [.init(identifier: identifier, events: [])])
    #expect(pool.status.contains("active=fallback"))
  }

  @Test func testDedicatedActivationReplacesTheSharedBootstrapDevice() async throws {
    let identifier = DeviceIdentifier(vendorID: 0x1234, productID: 0x5678)
    let bundleRoot = "/Applications/ConsumerA.app"
    let routeToken = UserSpaceVirtualDeviceConstants.dedicatedRouteToken(
      forConsumerBundleRootPath: bundleRoot
    )
    let shared = RecordingCompatibilityDispatcher(
      routeToken: UserSpaceVirtualDeviceConstants.sharedRouteToken
    )
    let dedicatedByRoute = LockedRouteDispatchers()
    let pool = try makePool(shared: shared, dedicatedByRoute: dedicatedByRoute)

    await pool.dispatch(events: [], from: identifier)
    try pool.ensureDedicatedRoute(forConsumerBundleRootPath: bundleRoot)

    let dedicated = try #require(dedicatedByRoute.dispatcherIfPresent(for: routeToken))
    #expect(dedicated.recordedDispatches.isEmpty)

    await pool.setActiveRouteToken(routeToken)

    #expect(shared.closeCount == 1)
    #expect(shared.status == "off")
    #expect(dedicated.recordedDispatches.map(\.events) == [[]])
    #expect(pool.status.contains("routes=1"))
  }

  @Test func testRouteHandoffNeutralizesAndClosesPreviousButtonState() async throws {
    let identifier = DeviceIdentifier(vendorID: 0x1234, productID: 0x5678)
    let firstBundleRoot = "/Applications/ConsumerA.app"
    let secondBundleRoot = "/Applications/ConsumerB.app"
    let firstRoute = UserSpaceVirtualDeviceConstants.dedicatedRouteToken(
      forConsumerBundleRootPath: firstBundleRoot
    )
    let secondRoute = UserSpaceVirtualDeviceConstants.dedicatedRouteToken(
      forConsumerBundleRootPath: secondBundleRoot
    )
    let shared = RecordingCompatibilityDispatcher(routeToken: "shared")
    let dedicatedByRoute = LockedRouteDispatchers()
    let pool = try makePool(shared: shared, dedicatedByRoute: dedicatedByRoute)

    try pool.ensureDedicatedRoute(forConsumerBundleRootPath: firstBundleRoot)
    try pool.ensureDedicatedRoute(forConsumerBundleRootPath: secondBundleRoot)
    await pool.setActiveRouteToken(firstRoute)
    await pool.dispatch(events: [.buttonPressed(.a)], from: identifier)
    await pool.setActiveRouteToken(secondRoute)

    let first = try #require(dedicatedByRoute.dispatcherIfPresent(for: firstRoute))
    let second = try #require(dedicatedByRoute.dispatcherIfPresent(for: secondRoute))
    #expect(first.recordedDispatches.map(\.events).contains([.buttonReleased(.a)]))
    #expect(first.closeCount >= 1)
    #expect(second.recordedDispatches.map(\.events).contains([.buttonPressed(.a)]))
    #expect(pool.status.contains("routes=1"))
  }

  @Test func testRouteHandoffNeutralizesPreviousActiveDpadState() async throws {
    let identifier = DeviceIdentifier(vendorID: 0x1234, productID: 0x5678)
    let firstBundleRoot = "/Applications/ConsumerA.app"
    let secondBundleRoot = "/Applications/ConsumerB.app"
    let firstRoute = UserSpaceVirtualDeviceConstants.dedicatedRouteToken(
      forConsumerBundleRootPath: firstBundleRoot
    )
    let secondRoute = UserSpaceVirtualDeviceConstants.dedicatedRouteToken(
      forConsumerBundleRootPath: secondBundleRoot
    )
    let shared = RecordingCompatibilityDispatcher(routeToken: "shared")
    let dedicatedByRoute = LockedRouteDispatchers()
    let pool = try makePool(shared: shared, dedicatedByRoute: dedicatedByRoute)

    try pool.ensureDedicatedRoute(forConsumerBundleRootPath: firstBundleRoot)
    try pool.ensureDedicatedRoute(forConsumerBundleRootPath: secondBundleRoot)
    await pool.setActiveRouteToken(firstRoute)
    await pool.dispatch(events: [.dpadChanged(.north)], from: identifier)
    await pool.setActiveRouteToken(secondRoute)

    let first = try #require(dedicatedByRoute.dispatcherIfPresent(for: firstRoute))
    let second = try #require(dedicatedByRoute.dispatcherIfPresent(for: secondRoute))
    #expect(first.recordedDispatches.map(\.events).contains([.dpadChanged(.neutral)]))
    #expect(second.recordedDispatches.map(\.events).contains([.dpadChanged(.north)]))
  }

  @Test func testNoActiveConsumerRestoresOneNeutralSharedFallback() async throws {
    let identifier = DeviceIdentifier(vendorID: 0x1234, productID: 0x5678)
    let bundleRoot = "/Applications/ConsumerA.app"
    let routeToken = UserSpaceVirtualDeviceConstants.dedicatedRouteToken(
      forConsumerBundleRootPath: bundleRoot
    )
    let shared = RecordingCompatibilityDispatcher(routeToken: "shared")
    let dedicatedByRoute = LockedRouteDispatchers()
    let pool = try makePool(shared: shared, dedicatedByRoute: dedicatedByRoute)

    await pool.dispatch(events: [], from: identifier)
    try pool.ensureDedicatedRoute(forConsumerBundleRootPath: bundleRoot)
    await pool.setActiveRouteToken(routeToken)
    await pool.setActiveRouteToken(nil)
    pool.retainDedicatedRoutes(forConsumerBundleRootPaths: [])

    let dedicated = try #require(dedicatedByRoute.dispatcherIfPresent(for: routeToken))
    #expect(dedicated.closeCount >= 1)
    #expect(shared.recordedDispatches.count == 2)
    #expect(shared.status == "on")
    #expect(pool.retainedDedicatedRouteCount == 0)
    #expect(pool.status.contains("routes=1"))
    #expect(pool.status.contains("active=fallback"))
  }

  @Test func testPhysicalControllerStopReachesEveryChildAndClearsFuturePriming() async throws {
    let identifier = DeviceIdentifier(vendorID: 0x1234, productID: 0x5678)
    let firstBundleRoot = "/Applications/ConsumerA.app"
    let secondBundleRoot = "/Applications/ConsumerB.app"
    let firstRoute = UserSpaceVirtualDeviceConstants.dedicatedRouteToken(
      forConsumerBundleRootPath: firstBundleRoot
    )
    let secondRoute = UserSpaceVirtualDeviceConstants.dedicatedRouteToken(
      forConsumerBundleRootPath: secondBundleRoot
    )
    let shared = RecordingCompatibilityDispatcher(routeToken: "shared")
    let dedicatedByRoute = LockedRouteDispatchers()
    let pool = try makePool(shared: shared, dedicatedByRoute: dedicatedByRoute)

    await pool.dispatch(events: [], from: identifier)
    try pool.ensureDedicatedRoute(forConsumerBundleRootPath: firstBundleRoot)
    await pool.setActiveRouteToken(firstRoute)
    pool.controllerDidStop(identifier)
    try pool.ensureDedicatedRoute(forConsumerBundleRootPath: secondBundleRoot)

    let first = try #require(dedicatedByRoute.dispatcherIfPresent(for: firstRoute))
    let second = try #require(dedicatedByRoute.dispatcherIfPresent(for: secondRoute))
    #expect(shared.stoppedIdentifiers == [identifier])
    #expect(first.stoppedIdentifiers == [identifier])
    #expect(second.recordedDispatches.isEmpty)
  }

  @Test func testInactiveDedicatedRoutesAreClosedAndPruned() async throws {
    let firstBundleRoot = "/Applications/ConsumerA.app"
    let secondBundleRoot = "/Applications/ConsumerB.app"
    let firstRoute = UserSpaceVirtualDeviceConstants.dedicatedRouteToken(
      forConsumerBundleRootPath: firstBundleRoot
    )
    let secondRoute = UserSpaceVirtualDeviceConstants.dedicatedRouteToken(
      forConsumerBundleRootPath: secondBundleRoot
    )
    let shared = RecordingCompatibilityDispatcher(routeToken: "shared")
    let dedicatedByRoute = LockedRouteDispatchers()
    let pool = try makePool(shared: shared, dedicatedByRoute: dedicatedByRoute)

    try pool.ensureDedicatedRoute(forConsumerBundleRootPath: firstBundleRoot)
    try pool.ensureDedicatedRoute(forConsumerBundleRootPath: secondBundleRoot)
    await pool.setActiveRouteToken(firstRoute)
    pool.retainDedicatedRoutes(forConsumerBundleRootPaths: [firstBundleRoot])

    let second = try #require(dedicatedByRoute.dispatcherIfPresent(for: secondRoute))
    #expect(second.closeCount == 1)
    #expect(pool.retainedDedicatedRouteCount == 1)
  }

  private func makePool(
    shared: RecordingCompatibilityDispatcher,
    dedicatedByRoute: LockedRouteDispatchers
  ) throws -> ForegroundConsumerCompatibilityDispatcherPool {
    try ForegroundConsumerCompatibilityDispatcherPool { requestedRouteToken in
      if let requestedRouteToken { return dedicatedByRoute.dispatcher(for: requestedRouteToken) }
      return shared
    }
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
}

private final class RecordingCompatibilityDispatcher: CompatibilityUserSpaceOutputDispatching,
  ControllerLifecycleListener, @unchecked Sendable
{
  struct RecordedDispatch: Sendable, Equatable {
    let identifier: DeviceIdentifier
    let events: [ControllerEvent]
  }

  let routeToken: String
  private let lock = NSLock()
  private var _suppressOutput = false
  private var _status = "off"
  private var _lastRumbleStatus = "none"
  private var _recordedDispatches: [RecordedDispatch] = []
  private var _closeCount = 0
  private var _stoppedIdentifiers: [DeviceIdentifier] = []

  init(routeToken: String) { self.routeToken = routeToken }

  var suppressOutput: Bool {
    get { lock.withLock { _suppressOutput } }
    set { lock.withLock { _suppressOutput = newValue } }
  }

  var status: String { lock.withLock { _status } }
  var lastRumbleStatus: String { lock.withLock { _lastRumbleStatus } }
  var recordedDispatches: [RecordedDispatch] { lock.withLock { _recordedDispatches } }
  var closeCount: Int { lock.withLock { _closeCount } }
  var stoppedIdentifiers: [DeviceIdentifier] { lock.withLock { _stoppedIdentifiers } }

  func close() {
    lock.withLock {
      _closeCount += 1
      _status = "off"
    }
  }

  func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) {
    lock.withLock {
      _status = "on"
      _recordedDispatches.append(.init(identifier: identifier, events: events))
    }
  }

  func controllerDidStop(_ identifier: DeviceIdentifier) {
    lock.withLock {
      _stoppedIdentifiers.append(identifier)
      _status = "off"
    }
  }
}
