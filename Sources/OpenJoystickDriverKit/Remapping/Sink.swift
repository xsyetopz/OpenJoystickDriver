import Foundation

/// A point-in-time authorization for one routing operation to reach the system-input sink.
///
/// Permits are invalidated whenever profile mutation starts or completes and when routing
/// terminates. They are intentionally opaque outside OpenJoystickDriverKit.
public struct RemappingEmissionPermit: Sendable {
  let revision: UInt64
  let owner: UUID?
}

/// The result of atomically closing ordinary output admission for a transaction.
public enum RemappingTransactionAdmission: Sendable {
  case admitted(RemappingEmissionPermit)
  case transactionAlreadyActive
  case terminated
}

/// Keeps one already-admitted output operation visible to transaction and shutdown drains.
///
/// Finishing is idempotent. The lease also finishes on deinitialization so cancellation and
/// thrown errors cannot strand admission closed forever.
public final class RemappingEmissionLease: @unchecked Sendable {
  public let permit: RemappingEmissionPermit
  private let id: UUID
  private let barrier: RemappingEmissionBarrier

  init(
    id: UUID,
    permit: RemappingEmissionPermit,
    barrier: RemappingEmissionBarrier
  ) {
    self.id = id
    self.permit = permit
    self.barrier = barrier
  }

  deinit {
    finish()
  }

  public func finish() {
    barrier.finishLease(id: id)
  }
}

/// Synchronizes routing admission with the engine's final synchronous sink boundary.
///
/// The lock protects only admission state and lease accounting. Arbitrary sink and dispatcher
/// code always runs after it is released, and no caller holds it across a suspension point.
public final class RemappingEmissionBarrier: @unchecked Sendable {
  private enum State {
    case open(revision: UInt64)
    case transaction(revision: UInt64, owner: UUID)
    case terminated(revision: UInt64)
  }

  private let lock = NSLock()
  private var state = State.open(revision: 0)
  private var activeLeaseIDs: Set<UUID> = []
  private var drainWaiters: [CheckedContinuation<Void, Never>] = []

  public init() {}

  public func currentPermit() -> RemappingEmissionPermit? {
    lock.withLock {
      guard case .open(let revision) = state else { return nil }
      return RemappingEmissionPermit(revision: revision, owner: nil)
    }
  }

  /// Admits one ordinary output operation while routing is open.
  ///
  /// The returned lease must cover the operation's complete asynchronous lifetime, including
  /// arbitrary compatibility dispatchers. A transaction or termination closes admission first
  /// and then waits for every lease acquired here to finish.
  public func acquireLease() -> RemappingEmissionLease? {
    acquireLease { state in
      guard case .open(let revision) = state else { return nil }
      return RemappingEmissionPermit(revision: revision, owner: nil)
    }
  }

  /// Atomically closes ordinary admission for `owner`, then waits for prior work to finish.
  public func suspend(owner: UUID) async -> RemappingTransactionAdmission {
    let initial = lock.withLock { () -> RemappingTransactionAdmission in
      switch state {
      case .open(let revision):
        let permit = RemappingEmissionPermit(revision: revision &+ 1, owner: owner)
        state = .transaction(revision: permit.revision, owner: owner)
        return .admitted(permit)
      case .transaction:
        return .transactionAlreadyActive
      case .terminated:
        return .terminated
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

  public func transactionPermit(owner: UUID) -> RemappingEmissionPermit? {
    lock.withLock {
      guard case .transaction(let revision, let activeOwner) = state,
        activeOwner == owner
      else { return nil }
      return RemappingEmissionPermit(revision: revision, owner: owner)
    }
  }

  @discardableResult public func resume(owner: UUID) -> Bool {
    lock.withLock {
      guard case .transaction(let revision, let activeOwner) = state,
        activeOwner == owner
      else { return false }
      state = .open(revision: revision &+ 1)
      return true
    }
  }

  @discardableResult public func resume(_ permit: RemappingEmissionPermit) -> Bool {
    lock.withLock {
      guard case .transaction(let revision, let owner) = state,
        permit.revision == revision,
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
      case .terminated:
        break
      }
    }
    await waitUntilDrained()
  }

  public var isTerminated: Bool {
    lock.withLock {
      guard case .terminated = state else { return false }
      return true
    }
  }

  public func permits(_ permit: RemappingEmissionPermit) -> Bool {
    lock.withLock { permitsEmission(permit) }
  }

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

  func withTermination<Result>(_ body: () throws -> Result) throws -> Result {
    guard let lease = acquireLease({ state in
      guard case .terminated(let revision) = state else { return nil }
      return RemappingEmissionPermit(revision: revision, owner: nil)
    }) else {
      throw RemappingEventEngineError.outputSuspended
    }
    defer { lease.finish() }
    return try body()
  }

  func finishLease(id: UUID) {
    let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
      guard activeLeaseIDs.remove(id) != nil, activeLeaseIDs.isEmpty else { return [] }
      defer { drainWaiters.removeAll() }
      return drainWaiters
    }
    for waiter in waiters { waiter.resume() }
  }

  private func acquireLease(
    requiring permit: RemappingEmissionPermit
  ) -> RemappingEmissionLease? {
    acquireLease { state in
      guard Self.permitsEmission(permit, in: state) else { return nil }
      return permit
    }
  }

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

  private func permitsEmission(_ permit: RemappingEmissionPermit) -> Bool {
    Self.permitsEmission(permit, in: state)
  }

  private static func permitsEmission(
    _ permit: RemappingEmissionPermit,
    in state: State
  ) -> Bool {
    switch state {
    case .open(let revision):
      permit.owner == nil && permit.revision == revision
    case .transaction(let revision, let owner):
      permit.owner == owner && permit.revision == revision
    case .terminated:
      false
    }
  }
}

/// A platform-independent system-input action produced by ``RemappingEventEngine``.
///
/// Platform adapters translate these symbolic actions to the operating system's
/// input-injection API. Continuous amounts are normalized to `-1...1`.
public enum RemappingSystemInputAction: Equatable, Sendable {
  case modifierDown(RemappingKeyModifier)
  case modifierUp(RemappingKeyModifier)
  case keyDown(RemappingKeyboardKey)
  case keyUp(RemappingKeyboardKey)
  case mouseButtonDown(RemappingMouseButton)
  case mouseButtonUp(RemappingMouseButton)
  case mouseMoved(axis: RemappingPointerAxis, amount: Double)
  case scrolled(axis: RemappingPointerAxis, amount: Double)
}

/// Inward-owned port for delivering remapped keyboard and pointer actions.
///
/// `send(_:)` is synchronous so an engine transition cannot be interleaved while
/// modifiers and keys are being ordered. An implementation must throw when it
/// cannot establish that the action was delivered. The engine then neutralizes
/// every potentially held output and rejects further input until ``recover()``
/// succeeds.
public protocol RemappingSystemInputSink: AnyObject, Sendable {
  func send(_ action: RemappingSystemInputAction) throws
}

/// A stable error surface for remapping dispatch and fail-closed recovery.
public enum RemappingEventEngineError: Error, Equatable, LocalizedError, Sendable {
  case faulted
  case outputSuspended
  case sinkUnavailable

  public var errorDescription: String? {
    switch self {
    case .faulted:
      "System-input remapping is suspended until sink recovery succeeds."
    case .outputSuspended:
      "System-input remapping is suspended by routing admission."
    case .sinkUnavailable:
      "The system-input sink rejected a remapping action."
    }
  }
}
