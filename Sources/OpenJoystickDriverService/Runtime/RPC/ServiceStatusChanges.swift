import AppKit
import Foundation
import OpenJoystickDriverKit

/// Counts service status changes and holds waiters until the count moves or a test notification
/// is announced.
///
/// A test notification is one pending announcement at a time. The first wait to reach the service,
/// a held one at once or the next to arrive, takes it and the app that sent that wait answers
/// with `reportTestNotification`; the requests for it end with that outcome. Requests made while
/// one is pending join it. If no wait takes it within `pickupSeconds`, or the taker does not
/// report within `answerSeconds`, they end with `noAnswer`. A request whose caller leaves is
/// withdrawn; when the last one is withdrawn the announcement is abandoned: it is dropped, and
/// a report for it, even from an app that already took it, is refused. A wait that is cancelled
/// as it takes the announcement did not deliver it, so the announcement goes back to pending for
/// the next wait until `pickupSeconds` after the request.
///
/// The count follows `.ojdServiceStatusDidChange`, which the device manager, the permission
/// manager, the virtual output backends, the device pipelines (including an overdue input report)
/// and the remapping handlers post when what `getStatus` or the remapping snapshot reports
/// changes. The foreground application, which decides remapping eligibility, is observed here
/// through the workspace.
/// - Note: `@unchecked Sendable` because `generation` and `waiters` are guarded by `lock`.
final class ServiceStatusChanges: @unchecked Sendable {
  /// The pending test notification, with the requests that wait for its outcome.
  private final class Announcement {
    /// The identity that a wait and a report name.
    let id = UUID()
    /// The requests waiting for the outcome, by identifier.
    ///
    /// A request whose caller left gets nil.
    var requests: [UUID: CheckedContinuation<TestNotificationOutcome?, Never>]
    /// Whether a wait took the announcement.
    var taken = false
    /// When the pickup deadline falls; an announcement given back is picked up before it.
    let pickupBy: Date
    /// Names the deadline that is running, so an earlier deadline that fires late cannot end the
    /// announcement in a later phase.
    var deadlineToken = UUID()
    /// The task that ends the announcement when its deadline falls.
    var deadline: Task<Void, Never>?

    /// Creates an announcement for the request `id` that `request` resumes.
    init(
      _ id: UUID,
      _ request: CheckedContinuation<TestNotificationOutcome?, Never>,
      pickupBy: Date
    ) {
      requests = [id: request]
      self.pickupBy = pickupBy
    }
  }

  /// A wait that is held until the next change.
  private final class Waiter {
    /// The wait's continuation, resumed once with its reply.
    let continuation: CheckedContinuation<ServiceStatusReply, Never>
    /// The task that ends the wait when the hold time passes.
    var hold: Task<Void, Never>?

    /// Creates a waiter that resumes `continuation`.
    init(_ continuation: CheckedContinuation<ServiceStatusReply, Never>) {
      self.continuation = continuation
    }
  }

  /// Guards `generation`, `waiters`, `pending` and the deadlines.
  private let lock = NSLock()
  /// The identity of this service instance, which a revision carries.
  private let instance: UUID
  /// The count of status changes.
  private var generation: UInt64 = 0
  /// The held waits, by identity.
  private var waiters: [UUID: Waiter] = [:]
  /// The test notification announcement that waits for an answer.
  private var pending: Announcement?
  /// How long an announcement waits for a wait to take it, in seconds.
  private let pickupSeconds: TimeInterval
  /// How long a taker has to report the outcome, in seconds.
  private let answerSeconds: TimeInterval
  /// The center that posts the status changes.
  private let center: NotificationCenter
  /// The center that posts workspace activations.
  private let workspaceCenter: NotificationCenter
  /// The observers on both centers.
  private var observers: [NSObjectProtocol] = []

  // The hooks below belong to tests; set them before the first wait.
  /// Runs after a wait is registered as held.
  var heldWaitDidRegister: (@Sendable () -> Void)?
  /// Runs after a held wait ends because its task is cancelled or its hold time passes.
  var heldWaitDidRelease: (@Sendable () -> Void)?
  /// Runs after a held wait is chosen for an announcement and before its reply is delivered.
  var announcementWillReachWait: (@Sendable () -> Void)?
  /// Runs after a test notification request is withdrawn because its caller left.
  var testNotificationRequestDidWithdraw: (@Sendable () -> Void)?

  /// Creates a counter over the two notification centers.
  init(
    center: NotificationCenter = .default,
    workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
    instance: UUID = UUID(),
    pickupSeconds: TimeInterval = TestNotificationDeadlines.pickupSeconds,
    answerSeconds: TimeInterval = TestNotificationDeadlines.answerSeconds
  ) {
    self.pickupSeconds = pickupSeconds
    self.answerSeconds = answerSeconds
    self.center = center
    self.workspaceCenter = workspaceCenter
    self.instance = instance
    observers = [
      center.addObserver(forName: .ojdServiceStatusDidChange, object: nil, queue: nil) {
        [weak self] _ in self?.recordChange()
      }
    ]
    observers.append(
      workspaceCenter.addObserver(
        forName: NSWorkspace.didActivateApplicationNotification,
        object: nil,
        queue: nil
      ) { [weak self] _ in self?.recordChange() }
    )
  }

  deinit {
    for observer in observers {
      center.removeObserver(observer)
      workspaceCenter.removeObserver(observer)
    }
  }

  /// The number of waits held for the next change.
  var heldWaitCount: Int { lock.withLock { waiters.count } }

  /// Returns at once when `after` is nil (`firstRead`), differs from the current revision,
  /// including by service instance (`statusChange`), or a test notification waits for a taker
  /// (`testNotification`); otherwise waits for the next change, or for a test notification, and
  /// returns the current revision as `holdElapsed` after `holdSeconds` with none.
  ///
  /// A cancelled wait returns at once as `holdElapsed`.
  func wait(after: ServiceStatusRevision?, holdSeconds: TimeInterval) async -> ServiceStatusReply {
    let id = UUID()
    let reply = await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        let waiter = Waiter(continuation)
        let current = lock.withLock { () -> ServiceStatusReply? in
          let revision = ServiceStatusRevision(instance: instance, generation: generation)
          if Task.isCancelled { return ServiceStatusReply(revision: revision, event: .holdElapsed) }
          if let announcement = takePending() {
            return ServiceStatusReply(
              revision: revision,
              event: .testNotification,
              announcement: announcement
            )
          }
          guard let after else {
            return ServiceStatusReply(revision: revision, event: .firstRead)
          }
          guard after == revision else {
            return ServiceStatusReply(revision: revision, event: .statusChange)
          }
          waiters[id] = waiter
          return nil
        }
        if let current {
          continuation.resume(returning: current)
          return
        }
        let hold = Task { [weak self] in
          try? await Task.sleep(nanoseconds: UInt64(holdSeconds * 1_000_000_000))
          self?.release(id)
        }
        let answered = lock.withLock { () -> Bool in
          guard waiters[id] === waiter else { return true }
          waiter.hold = hold
          return false
        }
        if answered { hold.cancel() } else { heldWaitDidRegister?() }
      }
    } onCancel: {
      release(id)
    }
    guard Task.isCancelled, let announcement = reply.announcement else { return reply }
    giveBack(announcement)
    return ServiceStatusReply(revision: reply.revision, event: .holdElapsed)
  }

  /// Counts a change and ends every held wait with a status change reply.
  private func recordChange() {
    let (released, revision) = lock.withLock { () -> ([Waiter], ServiceStatusRevision) in
      generation &+= 1
      defer { waiters = [:] }
      return (
        Array(waiters.values), ServiceStatusRevision(instance: instance, generation: generation)
      )
    }
    for waiter in released {
      waiter.hold?.cancel()
      waiter.continuation.resume(
        returning: ServiceStatusReply(revision: revision, event: .statusChange)
      )
    }
  }

  /// Announces a test notification and returns how it ended, or nil when the caller left first.
  ///
  /// A held wait takes it at once; otherwise it stays pending until the next wait arrives or
  /// `pickupSeconds` pass.
  func announceTestNotification() async -> TestNotificationOutcome? {
    let requestID = UUID()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        let handoff = lock.withLock { () -> (Waiter, ServiceStatusReply)? in
          if Task.isCancelled {
            continuation.resume(returning: nil)
            return nil
          }
          if let pending {
            pending.requests[requestID] = continuation
            return nil
          }
          let announcement = Announcement(
            requestID,
            continuation,
            pickupBy: Date().addingTimeInterval(pickupSeconds)
          )
          pending = announcement
          schedule(announcement, after: pickupSeconds)
          return handToHeldWait(announcement)
        }
        if let handoff { deliver(handoff) }
      }
    } onCancel: {
      withdrawTestNotificationRequest(requestID)
    }
  }

  /// Gives `announcement` to a held wait, if one is held.
  ///
  /// Call with `lock` held.
  private func handToHeldWait(_ announcement: Announcement) -> (Waiter, ServiceStatusReply)? {
    guard let key = waiters.keys.first, let waiter = waiters.removeValue(forKey: key) else {
      return nil
    }
    announcement.taken = true
    schedule(announcement, after: answerSeconds)
    return (
      waiter,
      ServiceStatusReply(
        revision: ServiceStatusRevision(instance: instance, generation: generation),
        event: .testNotification,
        announcement: announcement.id
      )
    )
  }

  /// Resumes the wait of `handoff` with its reply.
  private func deliver(_ handoff: (Waiter, ServiceStatusReply)) {
    let (waiter, reply) = handoff
    waiter.hold?.cancel()
    announcementWillReachWait?()
    waiter.continuation.resume(returning: reply)
  }

  /// Puts announcement `id`, taken by a wait that was cancelled before it returned, back to
  /// pending: the next wait takes it, or a wait already held does at once.
  ///
  /// The pickup deadline stays the one the request set; when it has passed, the announcement ends
  /// with `noAnswer` and no wait, held or later, takes it.
  private func giveBack(_ id: UUID) {
    let handoff = lock.withLock { () -> (Waiter, ServiceStatusReply)? in
      guard let pending, pending.id == id, pending.taken else { return nil }
      pending.taken = false
      let remaining = pending.pickupBy.timeIntervalSinceNow
      schedule(pending, after: max(0, remaining))
      return remaining > 0 ? handToHeldWait(pending) : nil
    }
    if let handoff { deliver(handoff) }
  }

  /// Removes the request from the pending announcement, which is dropped with its last request.
  private func withdrawTestNotificationRequest(_ requestID: UUID) {
    let request = lock.withLock { () -> CheckedContinuation<TestNotificationOutcome?, Never>? in
      guard let pending, let request = pending.requests.removeValue(forKey: requestID) else {
        return nil
      }
      if pending.requests.isEmpty {
        pending.deadline?.cancel()
        self.pending = nil
      }
      return request
    }
    guard let request else { return }
    request.resume(returning: nil)
    testNotificationRequestDidWithdraw?()
  }

  /// Ends the pending announcement `id` with `outcome`, which is `shown`, `denied` or `failed`.
  ///
  /// Returns false when `id` is not pending and taken, because it ended already or never existed.
  func reportTestNotification(_ id: UUID, outcome: TestNotificationOutcome) -> Bool {
    let requests = lock.withLock { () -> [CheckedContinuation<TestNotificationOutcome?, Never>]? in
      guard let pending, pending.id == id, pending.taken else { return nil }
      pending.deadline?.cancel()
      self.pending = nil
      return Array(pending.requests.values)
    }
    guard let requests else { return false }
    for request in requests { request.resume(returning: outcome) }
    return true
  }

  /// Marks the pending announcement taken and starts its answer deadline.
  ///
  /// Call with `lock` held.
  private func takePending() -> UUID? {
    guard let pending, !pending.taken else { return nil }
    pending.taken = true
    schedule(pending, after: answerSeconds)
    return pending.id
  }

  /// Replaces the deadline of `announcement`.
  ///
  /// Call with `lock` held.
  private func schedule(_ announcement: Announcement, after seconds: TimeInterval) {
    announcement.deadline?.cancel()
    let id = announcement.id
    let token = UUID()
    announcement.deadlineToken = token
    announcement.deadline = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      guard !Task.isCancelled else { return }
      self?.expire(id, token: token)
    }
  }

  /// Ends announcement `id` with `noAnswer` if `token` is still its running deadline.
  func expire(_ id: UUID, token: UUID) {
    let requests = lock.withLock { () -> [CheckedContinuation<TestNotificationOutcome?, Never>]? in
      guard let pending, pending.id == id, pending.deadlineToken == token else { return nil }
      self.pending = nil
      return Array(pending.requests.values)
    }
    for request in requests ?? [] { request.resume(returning: .noAnswer) }
  }

  /// Ends the held wait `id` with a hold-elapsed reply.
  private func release(_ id: UUID) {
    let (waiter, revision) = lock.withLock {
      (
        waiters.removeValue(forKey: id),
        ServiceStatusRevision(instance: instance, generation: generation)
      )
    }
    waiter?.hold?.cancel()
    waiter?.continuation.resume(
      returning: ServiceStatusReply(revision: revision, event: .holdElapsed)
    )
    if waiter != nil { heldWaitDidRelease?() }
  }
}
