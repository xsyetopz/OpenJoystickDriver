import Foundation

/// Common interface for virtual HID profile outputs.
public protocol VirtualOutputDispatching: OutputDispatcher {
  /// Backend status for UI and CLI reporting.
  var status: VirtualOutputBackendStatus { get }
  /// Most recent app-originated rumble report summary, or `nil` before any rumble report.
  var lastRumbleStatus: String? { get }
  /// Forces creation and neutral activation of every supplied virtual device.
  func activate(for identifiers: [LogicalControllerID]) async throws
  /// Updates suppression and waits for any required output barrier.
  func setOutputSuppressed(_ suppressed: Bool) async
  /// Drains and tears down user-space virtual HID devices owned by this output.
  func close() async
  /// Activates output for one controller while preserving publication failures.
  func activateOutputReportingFailure(for identifier: LogicalControllerID) async throws
}

/// Optional activation surface used to enforce a deadline for each controller in a set.
public protocol VirtualOutputControllerActivating: AnyObject, Sendable {
  /// Creates and activates the virtual device of `identifier`.
  ///
  /// - Throws: An error when the controller's virtual device cannot be activated.
  func activate(controller identifier: LogicalControllerID) async throws
}

/// Optional output-dispatcher hook for controller lifecycle events.
///
/// `DevicePipeline` calls this when a physical controller pipeline stops so output backends
/// can tear down any per-controller virtual devices.
public protocol ControllerLifecycleListener: AnyObject, Sendable {
  /// Called when the pipeline of the controller `identifier` stops.
  func controllerDidStop(_ identifier: LogicalControllerID) async
}

/// Receives physical input ownership before controller input or virtual activation is admitted.
public protocol ControllerInputOwnershipListener: AnyObject, Sendable {
  /// Reports the ownership observed for the physical input of the controller `identifier`.
  func controllerInputOwnershipChanged(
    _ ownership: HIDInputOwnership,
    for identifier: LogicalControllerID
  ) async
}

extension VirtualOutputDispatching {
  /// Sets ``OutputDispatcher/suppressOutput``.
  public func setOutputSuppressed(_ suppressed: Bool) { suppressOutput = suppressed }
  /// Activates output for `identifier`; this default reports no failure.
  public func activateOutputReportingFailure(for identifier: LogicalControllerID) async {
    await activateOutput(for: identifier)
  }
}

/// Tells an observe-only pipeline whether any consumer uses its controller's input, so a native
/// gamepad with no remapping costs no per-report dispatch.
///
/// The answer follows route changes, so a profile selected later takes effect without
/// reconnecting.
public protocol ObservedInputDemand: AnyObject, Sendable {
  /// Whether any consumer uses the input of the controller `identifier`.
  func wantsObservedInput(from identifier: LogicalControllerID) -> Bool
}

/// Tells a pipeline whether the active profile of a controller binds a pointer axis, so the
/// driver turns on the pointer hardware only while a consumer reads it.
///
/// The answer follows route changes, so a profile activated later takes effect without
/// reconnecting.
public protocol PointerInputDemand: AnyObject, Sendable {
  /// Whether the active profile of the controller `identifier` binds `PointerX` or `PointerY`.
  func wantsPointerInput(from identifier: LogicalControllerID) -> Bool
}

/// Takes controller state snapshots and sends them to an output target.
///
/// Implement this inward-owned port to decide what happens when controller state changes.
/// Production adapters live in their owning transport targets; the kit provides
/// ``LoggingOutputDispatcher`` for diagnostics.
public protocol OutputDispatcher: OutputSink {
  /// When `true`, all report/event output is suppressed (e.g. during developer
  /// packet capture). Implementations should invalidate any cached state on change.
  var suppressOutput: Bool { get set }
  /// Sets ``suppressOutput``.
  func setOutputSuppressed(_ suppressed: Bool) async

  /// Receives one controller's full state and writes it to the output.
  ///
  /// Called by ``DevicePipeline`` when the state changes or a report carries samples, and again
  /// with an unchanged state to activate output for the controller.
  /// - Parameters:
  ///   - event: The controller's state and the samples of the report that produced it.
  ///   - identifier: Which controller the state came from.
  func dispatch(
    _ event: ControllerEvent,
    from identifier: LogicalControllerID
  ) async

  /// Ensures output exists for the controller, for example a virtual device, without new input.
  ///
  /// Called by the pipeline and discovery once a controller's session can publish, and again
  /// after it resumes or reconnects.
  func activateOutput(for identifier: LogicalControllerID) async

  /// Dispatches like ``dispatch(_:from:)`` while preserving publication failures for
  /// recovery coordinators, and calls `onPublished` right after the report reaches the virtual
  /// device. `onPublished` is not called when output is suppressed or the publish fails.
  func dispatchPublishing(
    _ event: ControllerEvent,
    from identifier: LogicalControllerID,
    onPublished: @escaping @Sendable () -> Void
  ) async throws
}

extension OutputDispatcher {
  /// Sets ``suppressOutput``.
  public func setOutputSuppressed(_ suppressed: Bool) { suppressOutput = suppressed }

  /// Dispatchers that do not publish to a virtual device never report a publication.
  @preconcurrency
  public func dispatchPublishing(
    _ event: ControllerEvent,
    from identifier: LogicalControllerID,
    onPublished _: @Sendable () -> Void
  ) async {
    await dispatch(event, from: identifier)
  }
}

/// OutputDispatcher that logs controller events to debug output.
///
/// Used for hardware validation and testing. Production output uses a transport adapter.
public final class LoggingOutputDispatcher: OutputDispatcher, Sendable {
  // Suppression is ignored because this dispatcher is only for development.
  /// The diagnostic log, which receives the frames.
  public var destination: OutputDestination { .diagnosticLog }

  /// Accepted but ignored; this dispatcher always logs.
  private let storedSuppression = Locked(false)
  /// Whether output is suppressed; the dispatcher ignores it and always logs.
  public var suppressOutput: Bool {
    get { storedSuppression.withLock { $0 } }
    set { storedSuppression.withLock { $0 = newValue } }
  }

  /// Creates a dispatcher that logs each state.
  public init() {}

  /// Prints each state to standard output.
  public func dispatch(
    _ event: ControllerEvent,
    from identifier: LogicalControllerID
  ) {
    print(
      "[Output] "
        + "\(identifier.model.vendorID):\(identifier.model.productID)"
        + " -> \(event.state)"
    )
  }

  /// Nothing to activate: this dispatcher only logs.
  public func activateOutput(for _: LogicalControllerID) {}
}
