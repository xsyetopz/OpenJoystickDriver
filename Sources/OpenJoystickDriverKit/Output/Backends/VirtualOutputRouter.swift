import Foundation

/// Routes normalized controller input exclusively to the active virtual HID device.
public final class VirtualOutputRouter: OutputDispatcher, RemappingGamepadSink,
  RemappingGamepadOutputControlling, @unchecked Sendable
{
  /// Guards the state below.
  private let lock = NSLock()
  /// The backend that receives the output; nil when none is set.
  private var backend: (any OutputDispatcher)?
  /// Whether output is suppressed; the router passes the value to the backend.
  private var _suppressOutput = false
  /// Whether remapping output is suppressed; the router passes the value to the backend before it
  /// sends.
  private var remappingOutputSuppressed = false

  /// Whether output is suppressed; the router passes the value to the backend.
  public var suppressOutput: Bool {
    get { lock.withLock { _suppressOutput } }
    set {
      lock.withLock {
        _suppressOutput = newValue
        backend?.suppressOutput = newValue
      }
    }
  }

  /// Creates a router with no backend.
  public init() {}

  /// Sets the backend and passes the current suppression to it; nil removes the backend.
  public func setBackend(_ newBackend: (any OutputDispatcher)?) {
    lock.withLock {
      backend = newBackend
      backend?.suppressOutput = _suppressOutput
    }
  }

  /// Sets whether output from remapping is suppressed, and passes the value to a backend that
  /// controls it.
  public func setRemappingOutputSuppressed(_ suppressed: Bool) async {
    let target = lock.withLock {
      remappingOutputSuppressed = suppressed
      return backend
    }
    if let controlling = target as? any RemappingGamepadOutputControlling {
      await controlling.setRemappingOutputSuppressed(suppressed)
    }
  }

  /// Sends a remapped state to the backend.
  ///
  /// While remapping output is suppressed, only the neutral state reaches the backend.
  ///
  /// - Throws: `RemappingEventEngineError.sinkUnavailable` when the backend takes no remapped
  ///   state, or the error of the backend.
  public func send(_ state: RemappingGamepadState, for identifier: LogicalControllerID) async throws
  {
    let target = lock.withLock { remappingOutputSuppressed && state != .neutral ? nil : backend }
    guard let sink = target as? any RemappingGamepadSink else {
      throw RemappingEventEngineError.sinkUnavailable
    }
    if let controlling = target as? any RemappingGamepadOutputControlling {
      await controlling.setRemappingOutputSuppressed(lock.withLock { remappingOutputSuppressed })
    }
    try await sink.send(state, for: identifier)
  }

  /// Passes a controller event to the backend; nothing happens while output is suppressed.
  public func dispatch(
    _ event: ControllerEvent,
    from identifier: LogicalControllerID
  ) async {
    let target = lock.withLock { _suppressOutput ? nil : backend }
    await target?.dispatch(event, from: identifier)
  }

  /// Passes a controller event to the backend and reports its publication; nothing happens while
  /// output is suppressed.
  ///
  /// - Throws: The error of the backend.
  @preconcurrency
  public func dispatchPublishing(
    _ event: ControllerEvent,
    from identifier: LogicalControllerID,
    onPublished: @escaping @Sendable () -> Void
  ) async throws {
    let target = lock.withLock { _suppressOutput ? nil : backend }
    try await target?.dispatchPublishing(
      event,
      from: identifier,
      onPublished: onPublished
    )
  }

  /// Activates output for `identifier` on the backend; nothing happens while output is suppressed.
  public func activateOutput(for identifier: LogicalControllerID) async {
    let target = lock.withLock { _suppressOutput ? nil : backend }
    await target?.activateOutput(for: identifier)
  }
}

extension VirtualOutputRouter: ControllerInputOwnershipListener {
  /// Passes the change of the input ownership to a backend that listens for it.
  public func controllerInputOwnershipChanged(
    _ ownership: HIDInputOwnership,
    for identifier: LogicalControllerID
  ) async {
    let target = lock.withLock { backend }
    await (target as? any ControllerInputOwnershipListener)?.controllerInputOwnershipChanged(
      ownership,
      for: identifier
    )
  }
}

extension VirtualOutputRouter: ControllerLifecycleListener {
  /// Passes the stop of the controller to a backend that listens for it.
  public func controllerDidStop(_ identifier: LogicalControllerID) async {
    let target = lock.withLock { backend }
    if let listener = target as? any ControllerLifecycleListener {
      await listener.controllerDidStop(identifier)
    }
  }
}
