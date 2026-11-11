import Foundation

/// What the in-process service says about its request listener: the failure that stopped it, or nil
/// while it listens.
///
/// The app runs the service in its own process, so it reads this instead of the failure file,
/// which is for `ojd` and for a process that is not the service. The server sets the state; the app
/// observes it and calls ``restart`` to start the listener again.
public final class ServiceListenerState: @unchecked Sendable {
  /// Guards the stored values.
  private let lock = NSLock()
  /// The failure that stopped the listener; nil while it listens.
  private var current: ServiceListenerFailure?
  /// The closure called after every change of the failure.
  private var observer: (@Sendable () -> Void)?
  /// What ``restart()`` runs.
  private var restartAction: (@Sendable () throws -> Void)?

  /// Creates a state with no failure.
  public init() {}

  /// The failure that stopped the listener, or nil while it listens.
  public var failure: ServiceListenerFailure? { lock.withLock { current } }

  /// Sets what `observer` is told about: a call after every change of ``failure``.
  ///
  /// One observer is kept; setting another replaces it.
  @preconcurrency
  public func observe(_ observer: @escaping @Sendable () -> Void) {
    lock.withLock { self.observer = observer }
  }

  /// Sets the failure, or clears it with nil, and tells the observer.
  package func set(_ failure: ServiceListenerFailure?) {
    let observer = lock.withLock {
      current = failure
      return self.observer
    }
    observer?()
  }

  /// Sets what ``restart()`` runs.
  package func setRestart(_ action: (@Sendable () throws -> Void)?) {
    lock.withLock { restartAction = action }
  }

  /// Why ``restart()`` did not run.
  public enum RestartError: Error, Equatable, Sendable {
    /// The service has no listener to start: it is not started, or it is stopping.
    case unavailable
  }

  /// Starts the request listener again; a successful start clears ``failure``.
  ///
  /// Throws ``RestartError/unavailable`` before the service started and after it began to stop, and
  /// otherwise what the start throws.
  public func restart() throws {
    guard let action = lock.withLock({ restartAction }) else { throw RestartError.unavailable }
    try action()
  }
}
