import AppKit
import Foundation

/// Turns the workspace sleep and wake notifications into ordered events for an async handler.
///
/// The handler receives each event after the previous one finished.
/// - Note: `@unchecked Sendable` because `lock` guards every mutable property.
final class SystemPowerNotificationObserver: @unchecked Sendable {
  /// A system power change.
  enum Event: Equatable, Sendable {
    /// The system is about to sleep.
    case willSleep
    /// The system woke.
    case didWake
  }

  /// Handles one event and returns when it is done.
  typealias Handler = @Sendable (Event) async -> Void

  /// The center that posts the power notifications.
  private let notificationCenter: NotificationCenter
  /// Handles each event.
  private let handler: Handler
  /// Guards the mutable state below.
  private let lock = NSLock()
  /// The observers on the center.
  private var observerTokens: [NSObjectProtocol] = []
  /// The continuation of the stream of events.
  private var eventContinuation: AsyncStream<Event>.Continuation?
  /// The task that passes the events to the handler.
  private var deliveryTask: Task<Void, Never>?
  /// The task that stops the observer; shared by every caller of ``stop()``.
  private var stopTask: Task<Void, Never>?
  /// Whether ``start()`` ran.
  private var started = false
  /// Whether ``stop()`` ran, after which the observer delivers nothing.
  private var stopped = false

  /// Creates an observer of the workspace notification center.
  @MainActor
  convenience init(handler: @escaping Handler) {
    self.init(notificationCenter: NSWorkspace.shared.notificationCenter, handler: handler)
  }

  /// Creates an observer of `notificationCenter`.
  init(notificationCenter: NotificationCenter, handler: @escaping Handler) {
    self.notificationCenter = notificationCenter
    self.handler = handler
  }

  /// Starts observing sleep and wake notifications; does nothing after ``stop()``.
  func start() {
    lock.lock()
    defer { lock.unlock() }
    guard !started, !stopped else { return }
    started = true
    let eventStream = AsyncStream<Event>.makeStream(bufferingPolicy: .unbounded)
    eventContinuation = eventStream.continuation
    let handler = self.handler
    deliveryTask = Task { [weak self] in
      for await event in eventStream.stream {
        guard !Task.isCancelled, self?.canDeliver == true else { return }
        await handler(event)
      }
    }
    observerTokens = [
      notificationCenter.addObserver(
        forName: NSWorkspace.willSleepNotification,
        object: nil,
        queue: nil
      ) { [weak self] _ in self?.enqueue(.willSleep) },
      notificationCenter.addObserver(
        forName: NSWorkspace.didWakeNotification,
        object: nil,
        queue: nil
      ) { [weak self] _ in self?.enqueue(.didWake) },
    ]
  }

  /// Stops observing and returns when the delivery task has finished.
  func stop() async { await beginStop().value }

  /// Starts the stop once and returns its task.
  private func beginStop() -> Task<Void, Never> {
    lock.lock()
    guard let stopTask else {
      stopped = true
      started = false
      let tokens = observerTokens
      observerTokens.removeAll()
      eventContinuation?.finish()
      eventContinuation = nil
      let deliveryTask = deliveryTask
      let notificationCenter = notificationCenter
      let task = Task {
        for token in tokens { notificationCenter.removeObserver(token) }
        if let deliveryTask {
          deliveryTask.cancel()
          await deliveryTask.value
        }
      }
      stopTask = task
      lock.unlock()
      return task
    }
    lock.unlock()
    return stopTask
  }

  deinit {
    deliveryTask?.cancel()
    eventContinuation?.finish()
    for token in observerTokens { notificationCenter.removeObserver(token) }
  }

  /// Queues `event` for the handler while the observer runs.
  private func enqueue(_ event: Event) {
    lock.lock()
    guard started, !stopped else {
      lock.unlock()
      return
    }
    eventContinuation?.yield(event)
    lock.unlock()
  }

  /// Whether the observer runs, so the delivery task may still call the handler.
  private var canDeliver: Bool {
    lock.lock()
    defer { lock.unlock() }
    return started && !stopped
  }
}
