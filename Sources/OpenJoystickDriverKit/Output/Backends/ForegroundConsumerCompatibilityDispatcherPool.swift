import Foundation

/// Compatibility user-space output with exactly one live route per physical controller.
///
/// A neutral shared device bootstraps consumer discovery. Once a focused
/// consumer is identified, the shared device is closed and replaced by one
/// dedicated route. Inactive routes are closed and pruned.
public final class ForegroundConsumerCompatibilityDispatcherPool:
  CompatibilityUserSpaceOutputDispatching, @unchecked Sendable
{
  public typealias ChildFactory =
    @Sendable (String?) throws -> any CompatibilityUserSpaceOutputDispatching

  private struct DispatchTarget {
    let routeToken: String?
    let dispatcher: any CompatibilityUserSpaceOutputDispatching
  }

  private struct RouteTransition {
    let previousToken: String?
    let nextToken: String?
    let previousDispatcher: any CompatibilityUserSpaceOutputDispatching
    let nextDispatcher: any CompatibilityUserSpaceOutputDispatching
    let states: [DeviceIdentifier: DeviceInputState]
  }

  private let lock = NSLock()
  private let childFactory: ChildFactory
  private let sharedDispatcher: any CompatibilityUserSpaceOutputDispatching
  private var dedicatedDispatchers: [String: any CompatibilityUserSpaceOutputDispatching] = [:]
  private var activeRouteToken: String?
  private var knownIdentifiers: Set<DeviceIdentifier> = []
  private var currentStateByIdentifier: [DeviceIdentifier: DeviceInputState] = [:]
  private var _suppressOutput = false

  public init(childFactory: @escaping ChildFactory) throws {
    self.childFactory = childFactory
    self.sharedDispatcher = try childFactory(nil)
  }

  public var suppressOutput: Bool {
    get { lock.withLock { _suppressOutput } }
    set {
      let children = lock.withLock { () -> [any CompatibilityUserSpaceOutputDispatching] in
        _suppressOutput = newValue
        return [sharedDispatcher] + Array(dedicatedDispatchers.values)
      }
      for child in children {
        child.suppressOutput = newValue
      }
    }
  }

  public var status: String {
    lock.withLock {
      let activeLabel = activeRouteToken ?? "fallback"
      let childStatuses = [sharedDispatcher.status] + dedicatedDispatchers.values.map(\.status)
      if let errorStatus = childStatuses.first(where: { $0.hasPrefix("error:") }) {
        return errorStatus
      }
      let liveRouteCount = childStatuses.filter { $0 != "off" }.count
      if liveRouteCount == 0 { return "off" }
      return "on (routes=\(liveRouteCount), active=\(activeLabel))"
    }
  }

  public var lastRumbleStatus: String {
    lock.withLock {
      let active = dispatcherLocked(for: activeRouteToken)
      if active.lastRumbleStatus != "none" {
        return active.lastRumbleStatus
      }
      let all = [sharedDispatcher] + Array(dedicatedDispatchers.values)
      return all.first { $0.lastRumbleStatus != "none" }?.lastRumbleStatus ?? "none"
    }
  }

  var retainedDedicatedRouteCount: Int {
    lock.withLock { dedicatedDispatchers.count }
  }

  public func close() {
    let children = lock.withLock { () -> [any CompatibilityUserSpaceOutputDispatching] in
      let all = [sharedDispatcher] + Array(dedicatedDispatchers.values)
      dedicatedDispatchers.removeAll()
      activeRouteToken = nil
      knownIdentifiers.removeAll()
      currentStateByIdentifier.removeAll()
      return all
    }

    for child in children {
      child.close()
    }
  }

  public func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {
    let target = lock.withLock { () -> DispatchTarget? in
      knownIdentifiers.insert(identifier)
      var state =
        currentStateByIdentifier[identifier]
        ?? DeviceInputState(vendorID: identifier.vendorID, productID: identifier.productID)
      state.apply(events: events)
      currentStateByIdentifier[identifier] = state

      if let activeRouteToken {
        return DispatchTarget(
          routeToken: activeRouteToken,
          dispatcher: dispatcherLocked(for: activeRouteToken)
        )
      }
      guard events.isEmpty else { return nil }
      return DispatchTarget(routeToken: nil, dispatcher: sharedDispatcher)
    }

    guard let target else { return }
    await target.dispatcher.dispatch(events: events, from: identifier)

    let routeChanged = lock.withLock { activeRouteToken != target.routeToken }
    if routeChanged {
      // A handoff raced this dispatch. Closing prevents the old route from
      // recreating a stale IOHIDUserDevice after the transition completed.
      target.dispatcher.close()
    }
  }

  public func ensureDedicatedRoute(forConsumerBundleRootPath bundleRootPath: String) throws {
    let routeToken = UserSpaceVirtualDeviceConstants.dedicatedRouteToken(
      forConsumerBundleRootPath: bundleRootPath
    )

    if let existing = lock.withLock({ dedicatedDispatchers[routeToken] }) {
      existing.suppressOutput = suppressOutput
      return
    }

    let child = try childFactory(routeToken)
    child.suppressOutput = suppressOutput
    let inserted = lock.withLock { () -> Bool in
      guard dedicatedDispatchers[routeToken] == nil else { return false }
      dedicatedDispatchers[routeToken] = child
      return true
    }

    guard inserted else {
      // Concurrent route creation lost the insertion race.
      child.close()
      return
    }

    print(
      "[ForegroundConsumerCompatibilityDispatcherPool] Prepared dedicated Compatibility route "
        + "\(routeToken) for \(URL(fileURLWithPath: bundleRootPath).lastPathComponent)"
    )
  }

  public func retainDedicatedRoutes(forConsumerBundleRootPaths bundleRootPaths: Set<String>) {
    var retainedTokens = Set(
      bundleRootPaths.map {
        UserSpaceVirtualDeviceConstants.dedicatedRouteToken(
          forConsumerBundleRootPath: $0
        )
      }
    )

    let removed = lock.withLock { () -> [any CompatibilityUserSpaceOutputDispatching] in
      if let activeRouteToken,
        activeRouteToken != UserSpaceVirtualDeviceConstants.sharedRouteToken
      {
        retainedTokens.insert(activeRouteToken)
      }

      let staleTokens = dedicatedDispatchers.keys.filter { !retainedTokens.contains($0) }
      return staleTokens.compactMap { dedicatedDispatchers.removeValue(forKey: $0) }
    }

    for child in removed {
      child.close()
    }
  }

  public func setActiveRouteToken(_ requestedRouteToken: String?) async {
    let transition = lock.withLock { () -> RouteTransition? in
      let resolvedRouteToken = resolvedRouteTokenLocked(requestedRouteToken)
      let previousToken = activeRouteToken
      guard previousToken != resolvedRouteToken else { return nil }

      activeRouteToken = resolvedRouteToken
      return RouteTransition(
        previousToken: previousToken,
        nextToken: resolvedRouteToken,
        previousDispatcher: dispatcherLocked(for: previousToken),
        nextDispatcher: dispatcherLocked(for: resolvedRouteToken),
        states: currentStateByIdentifier
      )
    }

    guard let transition else { return }

    if transition.previousToken != nil {
      for (identifier, state) in transition.states {
        let neutralizingEvents = state.neutralizingEvents()
        if !neutralizingEvents.isEmpty {
          await transition.previousDispatcher.dispatch(
            events: neutralizingEvents,
            from: identifier
          )
        }
      }
    }
    transition.previousDispatcher.close()

    for (identifier, state) in transition.states {
      let events = transition.nextToken == nil ? [] : state.currentEvents()
      await transition.nextDispatcher.dispatch(events: events, from: identifier)
    }
  }

  private func resolvedRouteTokenLocked(_ requestedRouteToken: String?) -> String? {
    guard let requestedRouteToken else { return nil }
    if requestedRouteToken == UserSpaceVirtualDeviceConstants.sharedRouteToken {
      return requestedRouteToken
    }
    return dedicatedDispatchers[requestedRouteToken] == nil ? nil : requestedRouteToken
  }

  private func dispatcherLocked(
    for routeToken: String?
  ) -> any CompatibilityUserSpaceOutputDispatching {
    guard let routeToken else { return sharedDispatcher }
    if routeToken == UserSpaceVirtualDeviceConstants.sharedRouteToken {
      return sharedDispatcher
    }
    return dedicatedDispatchers[routeToken] ?? sharedDispatcher
  }
}

extension ForegroundConsumerCompatibilityDispatcherPool: ControllerLifecycleListener {
  public func controllerDidStop(_ identifier: DeviceIdentifier) {
    let children = lock.withLock { () -> [any CompatibilityUserSpaceOutputDispatching] in
      knownIdentifiers.remove(identifier)
      currentStateByIdentifier.removeValue(forKey: identifier)
      return [sharedDispatcher] + Array(dedicatedDispatchers.values)
    }

    for child in children {
      (child as? any ControllerLifecycleListener)?.controllerDidStop(identifier)
    }
  }
}
