import Foundation

/// Routes normalized controller input exclusively to the active compatibility virtual device.
public final class CompatibilityOutputDispatcher: OutputDispatcher, @unchecked Sendable {
  private let lock = NSLock()
  private var backend: (any OutputDispatcher)?
  private var _suppressOutput = false

  public var suppressOutput: Bool {
    get { lock.withLock { _suppressOutput } }
    set {
      lock.withLock {
        _suppressOutput = newValue
        backend?.suppressOutput = newValue
      }
    }
  }

  public init() {}

  public func setBackend(_ newBackend: (any OutputDispatcher)?) {
    lock.withLock {
      backend = newBackend
      backend?.suppressOutput = _suppressOutput
    }
  }

  public func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {
    let target = lock.withLock { _suppressOutput ? nil : backend }
    await target?.dispatch(events: events, from: identifier)
  }
}

extension CompatibilityOutputDispatcher: ControllerLifecycleListener {
  public func controllerDidStop(_ identifier: DeviceIdentifier) {
    let target = lock.withLock { backend }
    (target as? any ControllerLifecycleListener)?.controllerDidStop(identifier)
  }
}
