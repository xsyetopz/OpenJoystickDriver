import Foundation

/// Mirrors daemon-owned physical controller state into an app-owned Compatibility HID device.
///
/// macOS TCC grants Input Monitoring to GUI apps, not to the bundled launch agent in all
/// installs. Keeping IOHIDUserDevice creation in the app lets Compatibility mode use the
/// already-visible app permission row instead of asking users to grant a hidden daemon.
public final class AppOwnedCompatibilityOutputBridge: @unchecked Sendable {
  public typealias DispatcherFactory =
    @Sendable (CompatibilityIdentity) throws -> any CompatibilityUserSpaceOutputDispatching
  public typealias StateProvider =
    @Sendable (DeviceIdentifier) async -> DeviceInputState?

  private let lock = NSLock()
  private let dispatcherFactory: DispatcherFactory
  private var dispatcher: (any CompatibilityUserSpaceOutputDispatching)?
  private var identity: CompatibilityIdentity?
  private var currentStates: [DeviceIdentifier: DeviceInputState] = [:]
  private var _status = "off"

  public init(
    dispatcherFactory: @escaping DispatcherFactory = { identity in
      try UserSpaceOutputDispatcher.makeCompatibilityDispatcher(identity: identity)
    }
  ) {
    self.dispatcherFactory = dispatcherFactory
  }

  public var status: String {
    lock.withLock {
      dispatcher?.status ?? _status
    }
  }

  public func stop() {
    let old = lock.withLock { () -> (any CompatibilityUserSpaceOutputDispatching)? in
      let old = dispatcher
      dispatcher = nil
      identity = nil
      currentStates.removeAll()
      _status = "off"
      return old
    }
    old?.close()
  }

  public func update(
    isEnabled: Bool,
    identity requestedIdentity: CompatibilityIdentity,
    devices: [DeviceIdentifier],
    stateProvider: StateProvider
  ) async {
    guard isEnabled else {
      stop()
      return
    }

    let activeDispatcher: any CompatibilityUserSpaceOutputDispatching
    do {
      activeDispatcher = try ensureDispatcher(identity: requestedIdentity)
    } catch {
      lock.withLock {
        _status = "error: \(error)"
      }
      return
    }

    let known = Set(devices)
    let removed: [(DeviceIdentifier, DeviceInputState)] = lock.withLock {
      let removed = currentStates.filter { !known.contains($0.key) }
      for key in removed.keys {
        currentStates.removeValue(forKey: key)
      }
      return Array(removed)
    }

    for (identifier, state) in removed {
      let events = state.neutralizingEvents()
      if !events.isEmpty {
        await activeDispatcher.dispatch(events: events, from: identifier)
      }
    }

    for identifier in devices {
      guard let nextState = await stateProvider(identifier) else { continue }
      let events = lock.withLock { () -> [ControllerEvent] in
        defer { currentStates[identifier] = nextState }
        guard let previous = currentStates[identifier] else {
          return nextState.currentEvents()
        }
        guard previous != nextState else { return [] }
        return previous.neutralizingEvents() + nextState.currentEvents()
      }
      await activeDispatcher.dispatch(events: events, from: identifier)
    }
  }

  private func ensureDispatcher(
    identity requestedIdentity: CompatibilityIdentity
  ) throws -> any CompatibilityUserSpaceOutputDispatching {
    if let dispatcher = lock.withLock({ self.dispatcher }),
      lock.withLock({ self.identity }) == requestedIdentity
    {
      return dispatcher
    }

    let nextDispatcher = try dispatcherFactory(requestedIdentity)
    let old = lock.withLock { () -> (any CompatibilityUserSpaceOutputDispatching)? in
      let old = dispatcher
      dispatcher = nextDispatcher
      identity = requestedIdentity
      currentStates.removeAll()
      _status = nextDispatcher.status
      return old
    }
    old?.close()
    return nextDispatcher
  }
}
