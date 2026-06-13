import Foundation

/// Compatibility user-space output that keeps a single shared virtual device.
///
/// Real controller state is routed only to the currently active route token.
/// When no consumer route is active, the shared virtual device is neutralized.
public final class ForegroundConsumerCompatibilityDispatcherPool:
  CompatibilityUserSpaceOutputDispatching, @unchecked Sendable
{
  public typealias ChildFactory =
    @Sendable (String?) throws -> any CompatibilityUserSpaceOutputDispatching

  private let lock = NSLock()
  private let sharedDispatcher: any CompatibilityUserSpaceOutputDispatching
  private var activeRouteToken: String?
  private var knownIdentifiers: Set<DeviceIdentifier> = []
  private var currentStateByIdentifier: [DeviceIdentifier: DeviceInputState] = [:]
  private var _suppressOutput = false

  public init(childFactory: @escaping ChildFactory) throws {
    self.sharedDispatcher = try childFactory(nil)
  }

  public var suppressOutput: Bool {
    get { lock.withLock { _suppressOutput } }
    set {
      let child = lock.withLock { () -> any CompatibilityUserSpaceOutputDispatching in
        _suppressOutput = newValue
        return sharedDispatcher
      }
      child.suppressOutput = newValue
    }
  }

  public var status: String {
    lock.withLock {
      let activeLabel = activeRouteToken ?? "none"
      let childStatus = sharedDispatcher.status
      if childStatus.hasPrefix("error:") { return childStatus }
      if childStatus == "off" {
        return "off"
      }
      if childStatus != "on" {
        return "on (routes=1, active=\(activeLabel), child=\(childStatus))"
      }
      return "on (routes=1, active=\(activeLabel))"
    }
  }

  public var lastRumbleStatus: String {
    lock.withLock {
      sharedDispatcher.lastRumbleStatus
    }
  }

  public func close() {
    let child = lock.withLock { () -> any CompatibilityUserSpaceOutputDispatching in
      activeRouteToken = nil
      knownIdentifiers.removeAll()
      currentStateByIdentifier.removeAll()
      return sharedDispatcher
    }

    child.close()
  }

  public func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {
    let activeDispatcher = lock.withLock { () -> (any CompatibilityUserSpaceOutputDispatching)? in
      knownIdentifiers.insert(identifier)
      var state =
        currentStateByIdentifier[identifier]
        ?? DeviceInputState(vendorID: identifier.vendorID, productID: identifier.productID)
      state.apply(events: events)
      currentStateByIdentifier[identifier] = state
      if activeRouteToken == nil { return sharedDispatcher }
      return dispatcher(for: activeRouteToken)
    }

    if events.isEmpty {
      await sharedDispatcher.dispatch(events: [], from: identifier)
      return
    }

    guard let activeDispatcher else { return }
    await activeDispatcher.dispatch(events: events, from: identifier)
  }

  // swiftlint:disable:next async_without_await
  public func ensureDedicatedRoute(forConsumerBundleRootPath bundleRootPath: String) async throws {
    // Steam enumerates every IOHIDUserDevice we publish. Keep routing logical only:
    // one shared virtual controller, no per-consumer duplicate devices.
    _ = bundleRootPath
  }

  public func setActiveRouteToken(_ newActiveRouteToken: String?) async {
    let previousToken: String?
    let states: [DeviceIdentifier: DeviceInputState]

    (previousToken, states) = lock.withLock {
      let old = activeRouteToken
      guard old != newActiveRouteToken else { return (old, [:]) }
      activeRouteToken = newActiveRouteToken
      return (old, currentStateByIdentifier)
    }

    guard previousToken != newActiveRouteToken else { return }

    if let previousDispatcher = dispatcher(for: previousToken) {
      for (identifier, state) in states {
        let neutralizingEvents = state.neutralizingEvents()
        if !neutralizingEvents.isEmpty {
          await previousDispatcher.dispatch(events: neutralizingEvents, from: identifier)
        }
      }
    }

    if let nextDispatcher = dispatcher(for: newActiveRouteToken) {
      for (identifier, state) in states {
        let currentEvents = state.currentEvents()
        await nextDispatcher.dispatch(events: currentEvents, from: identifier)
      }
    }
  }

  private func dispatcher(
    for routeToken: String?
  ) -> (any CompatibilityUserSpaceOutputDispatching)? {
    if routeToken == nil { return nil }
    return sharedDispatcher
  }
}
