import Foundation

extension UserSpaceOutputDispatcher {
  /// The handler of the output commands that the host sends to a device.
  public typealias OutputCommandHandler =
    @Sendable (LogicalControllerID, ControllerOutputCommand) -> Void

  /// Why a virtual device could not be created.
  public enum CreationError: Error, CustomStringConvertible, Sendable {
    /// The host refused to create the device, or the retry policy still waits.
    case createFailed
    /// Input Monitoring is denied.
    case inputReadDenied
    /// Accessibility is denied.
    case inputInjectDenied
    /// The named entitlement is missing.
    case missingEntitlement(String)

    /// The text of the error.
    public var description: String {
      switch self {
      case .createFailed: return "Failed to create virtual HID device"
      case .inputReadDenied: return "Input Monitoring denied for the virtual HID device"
      case .inputInjectDenied: return "Accessibility denied for the virtual HID device"
      case .missingEntitlement(let entitlement): return "Missing entitlement: \(entitlement)"
      }
    }
  }

  /// Tracks whether the dispatcher is open.
  internal final class LifecycleState: Sendable {
    /// Whether the dispatcher is closed.
    private let closed = Locked(false)

    /// Whether the dispatcher is open.
    var isOpen: Bool { closed.withLock { !$0 } }

    /// Closes the dispatcher; returns whether this call closed it.
    func close() -> Bool {
      closed.withLock { closed in
        guard !closed else { return false }
        closed = true
        return true
      }
    }
  }

  /// Whether output is suppressed.
  public var suppressOutput: Bool {
    get { registryLock.withLock { _suppressOutput } }
    set { registryLock.withLock { _suppressOutput = newValue } }
  }

  /// The status of the backend.
  public var status: VirtualOutputBackendStatus { registryLock.withLock { _status } }
  /// Sets whether output is suppressed.
  ///
  /// Suppressing sends one neutral report to each device whose state does not come from
  /// remapping.
  public func setOutputSuppressed(_ suppressed: Bool) async {
    let suppression: (entries: [Entry], shouldNeutralize: Bool) = registryLock.withLock {
      let changed = !_suppressOutput && suppressed
      _suppressOutput = suppressed
      return (Array(entries.values), changed)
    }
    for entry in suppression.entries {
      _ = try? await entry.sender.submit {
        suppression.shouldNeutralize && !entry.inputReportState.isRemapped
          ? [entry.inputReportState.reset()] + entry.inputReportState.claimChangedAuxiliaryReports()
          : []
      }.value()
    }
  }
  /// Sets whether output from remapping is suppressed, and lets the queued reports settle.
  public func setRemappingOutputSuppressed(_ suppressed: Bool) async {
    let senders = registryLock.withLock {
      remappingOutputSuppressed = suppressed
      return entries.values.map(\.sender)
    }
    for sender in senders { _ = try? await sender.submit { [] }.value() }
  }

  /// The text of the latest rumble request from the host.
  public var lastRumbleStatus: String? { registryLock.withLock { _lastRumbleStatus } }

  /// Closes every device and waits until all are gone.
  public func close() async { await beginClose().value }

  /// Creates and neutrally activates one virtual device for each supplied controller.
  public func activate(for identifiers: [LogicalControllerID]) async throws {
    guard lifecycle.isOpen else { throw CancellationError() }
    var seen = Set<LogicalControllerID>()
    let identifiers = identifiers.filter { seen.insert($0).inserted }
    do {

      for identifier in identifiers {
        let entry = try await entry(for: identifier)
        guard lifecycle.isOpen else { throw CancellationError() }
        try await entry.sender.submit { [entry] in [entry.inputReportState.currentReport()] }
          .value()

      }
      withRegistry { recomputeStatusLocked() }
    } catch {
      await close()
      throw error
    }
  }

  /// Creates and neutrally activates the virtual device of `identifier`.
  ///
  /// - Throws: `CancellationError` when the dispatcher is closed, or the error of creating the
  ///   device. A failure closes the dispatcher.
  public func activate(controller identifier: LogicalControllerID) async throws {
    guard lifecycle.isOpen else { throw CancellationError() }
    do {
      let entry = try await entry(for: identifier)
      guard lifecycle.isOpen else { throw CancellationError() }
      try await entry.sender.submit { [entry] in [entry.inputReportState.currentReport()] }.value()
      withRegistry { recomputeStatusLocked() }
    } catch {
      await close()
      throw error
    }
  }

  /// Closes the dispatcher without waiting; the returned task ends when every device is gone.
  @discardableResult
  func beginClose() -> Task<Void, Never> {
    withRegistry {
      if let shutdownTask { return shutdownTask }
      _ = lifecycle.close()
      let resources = Array(entries.values)
      let identifiers = Set(entries.keys).union(creationTasks.keys)
      let tasks = Array(creationTasks.values)
      entries.removeAll()
      for identifier in identifiers { lifecycleGenerations[identifier, default: 0] &+= 1 }
      creationTasks.removeAll()
      creationRetryPolicies.removeAll()
      _status = .off
      for task in tasks { task.cancel() }
      let drains = resources.map { $0.beginClose() }
      let shutdown = Task {
        for drain in drains { await drain.value }
        for task in tasks { if let entry = try? await task.value { await entry.close() } }
      }
      shutdownTask = shutdown
      return shutdown
    }
  }

  /// Builds the report of a controller event and submits it; an error is dropped.
  public func dispatch(
    _ event: ControllerEvent,
    from identifier: LogicalControllerID
  ) async {
    try? await deliver(input: event.state, from: identifier, remappedState: nil)
  }

  /// Activates the device of `identifier` at its current state; an error is dropped.
  public func activateOutput(for identifier: LogicalControllerID) async {
    try? await deliver(input: nil, from: identifier, remappedState: nil)
  }

  /// Activates the device of `identifier` at its current state.
  ///
  /// - Throws: The error of creating the device or sending the report.
  public func activateOutputReportingFailure(for identifier: LogicalControllerID) async throws {
    try await deliver(input: nil, from: identifier, remappedState: nil)
  }

  /// Builds the report of a controller event and submits it; `onPublished` runs after the report
  /// reaches the device.
  ///
  /// - Throws: The error of creating the device or sending the report.
  @preconcurrency
  public func dispatchPublishing(
    _ event: ControllerEvent,
    from identifier: LogicalControllerID,
    onPublished: @escaping @Sendable () -> Void
  ) async throws {
    try await deliver(
      input: event.state,
      from: identifier,
      remappedState: nil,
      onPublished: onPublished
    )
  }

  /// Builds the report of a remapped state and submits it.
  ///
  /// The neutral state on a closed dispatcher closes it again.
  ///
  /// - Throws: The error of ``deliver(input:from:remappedState:onPublished:)``.
  public func send(_ state: RemappingGamepadState, for identifier: LogicalControllerID) async throws
  {
    if state == .neutral, !lifecycle.isOpen {
      await close()
      return
    }
    try await deliver(input: nil, from: identifier, remappedState: state)
  }

  /// Whether the output of remapping (`remapped`) or of the controller itself is suppressed.
  internal func isOutputSuppressed(remapped: Bool) -> Bool {
    registryLock.withLock { remapped ? remappingOutputSuppressed : _suppressOutput }
  }
}
