import Foundation

/// Authorization for one routing operation to reach the system-input sink at one point in time.
///
/// Permits are invalidated whenever profile mutation starts or completes and when routing
/// terminates. They are opaque outside OpenJoystickDriverKit.
public struct RemappingEmissionPermit: Sendable {
  /// Admission revision that the permit is valid for.
  let revision: UInt64
  /// Owner of the transaction that the permit belongs to, or `nil` for ordinary admission.
  let owner: UUID?
}

/// Result of atomically closing ordinary output admission for a transaction.
public enum RemappingTransactionAdmission: Sendable {
  /// Admission is closed, and the permit belongs to the transaction.
  case admitted(RemappingEmissionPermit)
  /// Another transaction owns admission.
  case transactionAlreadyActive
  /// Routing has terminated.
  case terminated
}

/// Keeps one already-admitted output operation visible to transaction and shutdown drains.
///
/// Finishing is idempotent. The lease also finishes on deinitialization, so cancellation and thrown
/// errors cannot strand admission closed forever.
public final class RemappingEmissionLease: Sendable {
  /// Permit that the lease covers.
  public let permit: RemappingEmissionPermit
  /// Identity of the lease in the accounting of the barrier.
  private let id: UUID
  /// Barrier that issued the lease.
  private let barrier: RemappingEmissionBarrier

  /// Creates a lease that the barrier already counts.
  init(id: UUID, permit: RemappingEmissionPermit, barrier: RemappingEmissionBarrier) {
    self.id = id
    self.permit = permit
    self.barrier = barrier
  }

  deinit { finish() }

  /// Ends the lease.
  ///
  /// Ending it again does nothing.
  public func finish() { barrier.finishLease(id: id) }
}

/// Synchronizes routing admission with the engine's final synchronous sink boundary.
///
/// The lock protects only admission state and lease accounting. Sink and dispatcher code runs after
/// it is released, and no caller holds it across a suspension point.
public final class RemappingEmissionBarrier: @unchecked Sendable {
  /// Admission state of the barrier.
  private enum State {
    /// Ordinary output is admitted at a revision.
    case open(revision: UInt64)
    /// Only the owner of a transaction is admitted.
    case transaction(revision: UInt64, owner: UUID)
    /// No output is admitted any more.
    case terminated(revision: UInt64)
  }

  /// Protects the state and the lease accounting.
  private let lock = NSLock()
  /// Current admission state.
  private var state = State.open(revision: 0)
  /// Identifiers of the leases that have not finished.
  private var activeLeaseIDs: Set<UUID> = []
  /// Callers waiting for every lease to finish.
  private var drainWaiters: [CheckedContinuation<Void, Never>] = []

  /// Creates a barrier that admits ordinary output.
  public init() {}

  /// Returns a permit for ordinary output while routing is open, otherwise `nil`.
  public func currentPermit() -> RemappingEmissionPermit? {
    lock.withLock {
      guard case .open(let revision) = state else { return nil }
      return RemappingEmissionPermit(revision: revision, owner: nil)
    }
  }

  /// Admits one ordinary output operation while routing is open.
  ///
  /// The returned lease must cover the complete asynchronous lifetime of the operation, including
  /// arbitrary virtual output dispatchers. A transaction or termination closes admission first and
  /// then waits for every lease acquired here to finish. Returns `nil` when routing is not open.
  public func acquireLease() -> RemappingEmissionLease? {
    acquireLease { state in
      guard case .open(let revision) = state else { return nil }
      return RemappingEmissionPermit(revision: revision, owner: nil)
    }
  }

  /// Atomically closes ordinary admission for `owner`, then waits for prior work to finish.
  ///
  /// Returns the transaction permit once every earlier lease has finished, or the reason that
  /// admission cannot be closed.
  public func suspend(owner: UUID) async -> RemappingTransactionAdmission {
    let initial = lock.withLock { () -> RemappingTransactionAdmission in
      switch state {
      case .open(let revision):
        let permit = RemappingEmissionPermit(revision: revision &+ 1, owner: owner)
        state = .transaction(revision: permit.revision, owner: owner)
        return .admitted(permit)
      case .transaction: return .transactionAlreadyActive
      case .terminated: return .terminated
      }
    }
    guard case .admitted(let permit) = initial else { return initial }
    await waitUntilDrained()
    return lock.withLock {
      guard case .transaction(let revision, let activeOwner) = state else {
        if case .terminated = state { return .terminated }
        return .transactionAlreadyActive
      }
      guard revision == permit.revision, activeOwner == owner else {
        return .transactionAlreadyActive
      }
      return .admitted(permit)
    }
  }

  /// Returns the permit of the transaction that `owner` holds, or `nil` when it holds none.
  public func transactionPermit(owner: UUID) -> RemappingEmissionPermit? {
    lock.withLock {
      guard case .transaction(let revision, let activeOwner) = state, activeOwner == owner else {
        return nil
      }
      return RemappingEmissionPermit(revision: revision, owner: owner)
    }
  }

  /// Ends the transaction of `owner` and reopens ordinary admission.
  ///
  /// Returns whether `owner` held the transaction. Permits of the transaction become invalid.
  @discardableResult
  public func resume(owner: UUID) -> Bool {
    lock.withLock {
      guard case .transaction(let revision, let activeOwner) = state, activeOwner == owner else {
        return false
      }
      state = .open(revision: revision &+ 1)
      return true
    }
  }

  /// Ends the transaction that a permit belongs to and reopens ordinary admission.
  ///
  /// Returns whether the permit belonged to the current transaction. Permits of the transaction
  /// become invalid.
  @discardableResult
  public func resume(_ permit: RemappingEmissionPermit) -> Bool {
    lock.withLock {
      guard case .transaction(let revision, let owner) = state, permit.revision == revision,
        permit.owner == owner
      else { return false }
      state = .open(revision: revision &+ 1)
      return true
    }
  }

  /// Permanently closes ordinary and transaction admission and drains prior leases.
  public func terminate() async {
    lock.withLock {
      switch state {
      case .open(let revision), .transaction(let revision, _):
        state = .terminated(revision: revision &+ 1)
      case .terminated: break
      }
    }
    await waitUntilDrained()
  }

  /// Whether routing has terminated.
  public var isTerminated: Bool {
    lock.withLock {
      guard case .terminated = state else { return false }
      return true
    }
  }

  /// Whether a permit is admitted now.
  public func permits(_ permit: RemappingEmissionPermit) -> Bool {
    lock.withLock { permitsEmission(permit) }
  }

  /// Runs a body under a lease for a permit.
  /// - Throws: ``RemappingEventEngineError/outputSuspended`` when the permit is not admitted, and
  ///   any error of the body.
  func withEmissionPermit<Result>(
    _ permit: RemappingEmissionPermit,
    _ body: () throws -> Result
  ) throws -> Result {
    guard let lease = acquireLease(requiring: permit) else {
      throw RemappingEventEngineError.outputSuspended
    }
    defer { lease.finish() }
    return try body()
  }

  /// Runs a body under a lease that is only available after termination.
  /// - Throws: ``RemappingEventEngineError/outputSuspended`` when routing has not terminated, and
  ///   any error of the body.
  func withTermination<Result>(_ body: () throws -> Result) throws -> Result {
    guard let lease = acquireTerminationLease() else {
      throw RemappingEventEngineError.outputSuspended
    }
    defer { lease.finish() }
    return try body()
  }

  /// Admits one operation after termination, or returns `nil` while routing is not terminated.
  func acquireTerminationLease() -> RemappingEmissionLease? {
    acquireLease { state in
      guard case .terminated(let revision) = state else { return nil }
      return RemappingEmissionPermit(revision: revision, owner: nil)
    }
  }

  /// Ends a lease and resumes the drain waiters when it was the last active one.
  func finishLease(id: UUID) {
    let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
      guard activeLeaseIDs.remove(id) != nil, activeLeaseIDs.isEmpty else { return [] }
      defer { drainWaiters.removeAll() }
      return drainWaiters
    }
    for waiter in waiters { waiter.resume() }
  }

  /// Admits one operation under a permit, or returns `nil` when the permit is not admitted.
  func acquireLease(requiring permit: RemappingEmissionPermit) -> RemappingEmissionLease? {
    acquireLease { state in
      guard Self.permitsEmission(permit, in: state) else { return nil }
      return permit
    }
  }

  /// Admits one operation when a rule gives a permit for the current state, and counts its lease.
  private func acquireLease(
    _ admittedPermit: (State) -> RemappingEmissionPermit?
  ) -> RemappingEmissionLease? {
    lock.withLock {
      guard let permit = admittedPermit(state) else { return nil }
      let id = UUID()
      activeLeaseIDs.insert(id)
      return RemappingEmissionLease(id: id, permit: permit, barrier: self)
    }
  }

  /// Suspends until no lease is active.
  private func waitUntilDrained() async {
    await withCheckedContinuation { continuation in
      let resumeImmediately = lock.withLock { () -> Bool in
        guard !activeLeaseIDs.isEmpty else { return true }
        drainWaiters.append(continuation)
        return false
      }
      if resumeImmediately { continuation.resume() }
    }
  }

  /// Whether a permit is admitted in the current state.
  private func permitsEmission(_ permit: RemappingEmissionPermit) -> Bool {
    Self.permitsEmission(permit, in: state)
  }

  /// Whether a permit is admitted in a state.
  ///
  /// Ordinary permits need an open state with the same revision. Transaction permits need the same
  /// owner and revision. Nothing is admitted after termination.
  private static func permitsEmission(_ permit: RemappingEmissionPermit, in state: State) -> Bool {
    switch state {
    case .open(let revision): permit.owner == nil && permit.revision == revision
    case .transaction(let revision, let owner): permit.owner == owner && permit.revision == revision
    case .terminated: false
    }
  }
}

/// A platform-independent system-input action produced by ``RemappingEventEngine``.
///
/// Platform adapters translate these symbolic actions to the input-injection API of the operating
/// system. Continuous amounts are normalized to `-1...1`.
public enum RemappingSystemInputAction: Equatable, Sendable {
  /// Presses a modifier key.
  case modifierDown(RemappingKeyModifier)
  /// Releases a modifier key.
  case modifierUp(RemappingKeyModifier)
  /// Presses a key.
  case keyDown(RemappingKeyboardKey)
  /// Releases a key.
  case keyUp(RemappingKeyboardKey)
  /// Presses a pointer button.
  case mouseButtonDown(RemappingMouseButton)
  /// Releases a pointer button.
  case mouseButtonUp(RemappingMouseButton)
  /// Moves the pointer continuously along an axis.
  case mouseMoved(axis: RemappingPointerAxis, amount: Double)
  /// Relative displacement in logical screen points, already integrated over sample time.
  case pointerDelta(x: Double, y: Double)
  /// Scrolls continuously along an axis.
  case scrolled(axis: RemappingPointerAxis, amount: Double)
  /// Integrated high-resolution scroll displacement in logical lines.
  case scrollDelta(deltaX: Double, deltaY: Double)
}

/// Port for delivering remapped keyboard and pointer actions.
///
/// `send(_:)` is synchronous so an engine transition cannot be interleaved while modifiers and keys
/// are being ordered. An implementation must throw when it cannot establish that the action was
/// delivered. The engine then neutralizes every potentially held output and rejects further input
/// until ``RemappingEventEngine/recover()`` succeeds.
public protocol RemappingSystemInputSink: AnyObject, Sendable {
  /// Delivers an action.
  /// - Throws: An error when delivery cannot be established.
  func send(_ action: RemappingSystemInputAction) throws
}

/// Errors of remapping dispatch and fail-closed recovery.
public enum RemappingEventEngineError: Error, Equatable, LocalizedError, Sendable {
  /// The engine is suspended until sink recovery succeeds.
  case faulted
  /// Routing admission refuses output.
  case outputSuspended
  /// A sink rejected an action or is missing.
  case sinkUnavailable

  /// Message that says why remapping output is suspended or a sink failed.
  public var errorDescription: String? {
    switch self {
    case .faulted: "System-input remapping is suspended until sink recovery succeeds."
    case .outputSuspended: "System-input remapping is suspended by routing admission."
    case .sinkUnavailable: "The system-input sink rejected a remapping action."
    }
  }
}

/// Delivers a complete remapped gamepad state through the virtual output backend.
///
/// Completion must mean delivery has finished; enqueueing a detached send is insufficient.
public protocol RemappingGamepadSink: AnyObject, Sendable {
  /// Delivers the complete gamepad state of a controller.
  func send(_ state: RemappingGamepadState, for identifier: LogicalControllerID) async throws
}

/// Delivers mapping-owned physical-controller channel claims for one exact input device.
public protocol RemappingPhysicalOutputSink: AnyObject, Sendable {
  /// Sets or releases the claim of an owner on a physical output channel.
  func set(
    _ output: RemappingPhysicalOutput,
    active: Bool,
    owner: UUID,
    for identifier: LogicalControllerID
  ) async throws
  /// Releases every claim on a controller.
  func releaseAll(for identifier: LogicalControllerID) async throws
  /// Sets the profile color of a controller, or clears it with `nil`.
  func setProfileColor(_ color: ControllerColor?, for identifier: LogicalControllerID) async throws
}

extension RemappingPhysicalOutputSink {
  /// Default that only yields, for sinks that do not show a profile color.
  public func setProfileColor(
    _ color: ControllerColor?,
    for identifier: LogicalControllerID
  ) async throws { await Task.yield() }
}

/// Preserves the order of transient presses, releases, and mixed destination actions.
enum RemappingEngineAction: Equatable, Sendable {
  /// A keyboard or pointer action.
  case system(RemappingSystemInputAction)
  /// The complete virtual gamepad state of a controller.
  case gamepad(RemappingGamepadState, LogicalControllerID)
  /// A physical output claim that an owner sets or releases for a controller.
  case physical(RemappingPhysicalOutput, active: Bool, owner: UUID, LogicalControllerID)
}

/// Separates remapping admission from the virtual output passthrough gate of a shared backend.
public protocol RemappingGamepadOutputControlling: AnyObject, Sendable {
  /// Sets whether remapping output is suppressed.
  func setRemappingOutputSuppressed(_ suppressed: Bool) async
}
