import Foundation

/// Turns the root power domain messages into ordered events for an async handler.
///
/// The handler receives each event after the previous one finished. The observer acknowledges a
/// sleep to the system only after the handler returned for that sleep, and exactly once, so the
/// system does not sleep before the teardown finishes. It allows an idle sleep at once and never
/// vetoes it. A teardown that does not return leaves the system to force the sleep after its own
/// timeout.
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

  /// An event and the notification ID of the sleep that waits for it, if any.
  private struct QueuedEvent: Sendable {
    /// The event for the handler.
    let event: Event
    /// The sleep to acknowledge after the handler returned.
    let sleepNotificationID: Int?
  }

  /// The source of power messages and the acknowledgement.
  private let powerSource: any SystemPowerSource
  /// Handles each event.
  private let handler: Handler
  /// Guards the mutable state below.
  private let lock = NSLock()
  /// The continuation of the stream of events.
  private var eventContinuation: AsyncStream<QueuedEvent>.Continuation?
  /// The task that passes the events to the handler.
  private var deliveryTask: Task<Void, Never>?
  /// The task that stops the observer; shared by every caller of ``stop()``.
  private var stopTask: Task<Void, Never>?
  /// Whether ``start()`` ran.
  private var started = false
  /// Whether ``stop()`` ran, after which the observer delivers nothing.
  private var stopped = false

  /// Creates an observer of the root power domain.
  convenience init(handler: @escaping Handler) {
    self.init(powerSource: IOKitSystemPowerSource(), handler: handler)
  }

  /// Creates an observer of `powerSource`.
  init(powerSource: any SystemPowerSource, handler: @escaping Handler) {
    self.powerSource = powerSource
    self.handler = handler
  }

  /// Starts observing sleep and wake messages; does nothing after ``stop()``.
  func start() {
    lock.lock()
    defer { lock.unlock() }
    guard !started, !stopped else { return }
    started = true
    let eventStream = AsyncStream<QueuedEvent>.makeStream(bufferingPolicy: .unbounded)
    eventContinuation = eventStream.continuation
    let handler = self.handler
    let powerSource = self.powerSource
    deliveryTask = Task { [weak self] in
      for await queued in eventStream.stream {
        let canDeliver = !Task.isCancelled && self?.canDeliver == true
        if canDeliver { await handler(queued.event) }
        if let id = queued.sleepNotificationID { powerSource.allowPowerChange(notificationID: id) }
        if !canDeliver { return }
      }
    }
    powerSource.start { [weak self] message in self?.receive(message) }
  }

  /// Stops observing and returns when the delivery task has finished.
  func stop() async { await beginStop().value }

  /// Starts the stop once and returns its task.
  private func beginStop() -> Task<Void, Never> {
    lock.lock()
    guard let stopTask else {
      stopped = true
      started = false
      eventContinuation?.finish()
      eventContinuation = nil
      let deliveryTask = deliveryTask
      let powerSource = powerSource
      let task = Task {
        if let deliveryTask {
          deliveryTask.cancel()
          await deliveryTask.value
        }
        powerSource.stop()
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
    powerSource.stop()
  }

  /// Queues the event of `message`, or allows an idle sleep at once.
  private func receive(_ message: SystemPowerMessage) {
    switch message {
    case .canSystemSleep(let id): powerSource.allowPowerChange(notificationID: id)
    case .systemWillSleep(let id): enqueue(QueuedEvent(event: .willSleep, sleepNotificationID: id))
    case .systemHasPoweredOn: enqueue(QueuedEvent(event: .didWake, sleepNotificationID: nil))
    }
  }

  /// Queues `queued` for the handler while the observer runs, or acknowledges a sleep it drops.
  private func enqueue(_ queued: QueuedEvent) {
    lock.lock()
    guard started, !stopped else {
      lock.unlock()
      if let id = queued.sleepNotificationID { powerSource.allowPowerChange(notificationID: id) }
      return
    }
    eventContinuation?.yield(queued)
    lock.unlock()
  }

  /// Whether the observer runs, so the delivery task may still call the handler.
  private var canDeliver: Bool {
    lock.lock()
    defer { lock.unlock() }
    return started && !stopped
  }
}
