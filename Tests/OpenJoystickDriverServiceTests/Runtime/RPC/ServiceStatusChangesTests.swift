import AppKit
import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit
@testable import OpenJoystickDriverService

@Suite(.timeLimit(.minutes(1)))
struct ServiceStatusChangesTests {
  /// Changes that observe private centers only, so an application another process activates
  /// during the run is no status change here.
  private static func isolated(
    center: NotificationCenter = NotificationCenter(),
    instance: UUID = UUID()
  ) -> ServiceStatusChanges {
    ServiceStatusChanges(center: center, workspaceCenter: NotificationCenter(), instance: instance)
  }

  private static func revision(_ changes: ServiceStatusChanges) async -> ServiceStatusRevision {
    await changes.wait(after: nil, holdSeconds: 30).revision
  }

  /// A stream that yields once for each wait that becomes held; set before the wait starts.
  private static func heldWaits(_ changes: ServiceStatusChanges) -> AsyncStream<Void> {
    let (registered, gate) = AsyncStream.makeStream(of: Void.self)
    changes.heldWaitDidRegister = { gate.yield() }
    return registered
  }

  /// Returns once the next wait has become held.
  private static func nextHeldWait(_ registered: AsyncStream<Void>) async {
    for await _ in registered { return }
  }

  @Test
  func aNilRevisionReadsTheCurrentOneAtOnce() async {
    let instance = UUID()
    let changes = Self.isolated(instance: instance)

    #expect(
      await changes.wait(after: nil, holdSeconds: 30)
        == ServiceStatusReply(
          revision: ServiceStatusRevision(instance: instance, generation: 0),
          event: .firstRead
        )
    )
  }

  @Test
  func aWaitReturnsOnAStatusNotification() async {
    let center = NotificationCenter()
    let changes = Self.isolated(center: center)
    let baseline = await Self.revision(changes)

    let registered = Self.heldWaits(changes)
    // The hold time exceeds the suite's time limit, so only the notification can end the wait.
    async let next = changes.wait(after: baseline, holdSeconds: 3600)
    await Self.nextHeldWait(registered)
    center.post(name: .ojdServiceStatusDidChange, object: nil)

    #expect(await next.revision.generation == 1)
  }

  @Test
  func aChangeBeforeTheWaitAnswersAtOnce() async {
    let center = NotificationCenter()
    let changes = Self.isolated(center: center)
    let baseline = await Self.revision(changes)
    center.post(name: .ojdServiceStatusDidChange, object: nil)

    #expect(await changes.wait(after: baseline, holdSeconds: 30).revision.generation == 1)
  }

  @Test
  func aWaitWithNoChangeReturnsTheSameRevisionAfterTheHoldTime() async {
    let changes = Self.isolated()
    let baseline = await Self.revision(changes)

    #expect(
      await changes.wait(after: baseline, holdSeconds: 0.05)
        == ServiceStatusReply(revision: baseline, event: .holdElapsed)
    )
  }

  @Test
  func aRestartedServiceDiffersEvenWithTheSameGeneration() async {
    let old = ServiceStatusRevision(instance: UUID(), generation: 0)
    let changes = Self.isolated()

    let revision = await changes.wait(after: old, holdSeconds: 30).revision

    #expect(revision.generation == old.generation)
    #expect(revision.instance != old.instance)
  }

  @Test
  func anApplicationActivationIsAStatusChange() async {
    let workspace = NotificationCenter()
    let changes = ServiceStatusChanges(center: NotificationCenter(), workspaceCenter: workspace)
    let baseline = await Self.revision(changes)

    workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)

    #expect(await changes.wait(after: baseline, holdSeconds: 30).revision.generation == 1)
  }

  @Test
  func aCancelledWaitReturnsAtOnceWithoutWaitingForTheHoldTime() async {
    let changes = Self.isolated()
    let baseline = await Self.revision(changes)
    // The hold time exceeds the test's time limit, so only the cancellation can end the wait.
    let task = Task { await changes.wait(after: baseline, holdSeconds: 3600) }
    task.cancel()

    #expect(await task.value == ServiceStatusReply(revision: baseline, event: .holdElapsed))
  }

  @Test
  func theSharedPostAnnouncesAChange() async {
    let changes = ServiceStatusChanges(workspaceCenter: NotificationCenter())
    let baseline = await Self.revision(changes)

    NotificationCenter.postServiceStatusChanged(from: changes)

    #expect(
      await changes.wait(after: baseline, holdSeconds: 30).revision.generation > baseline.generation
    )
  }

  private static func announcementID(_ reply: ServiceStatusReply) -> UUID? {
    guard reply.event == .testNotification else { return nil }
    return reply.announcement
  }

  @Test
  func aHeldWaitTakesTheAnnouncementAndTheReportEndsTheRequest() async throws {
    let changes = ServiceStatusChanges(center: NotificationCenter())
    let baseline = await Self.revision(changes)
    let registered = Self.heldWaits(changes)
    async let held = changes.wait(after: baseline, holdSeconds: 30)
    await Self.nextHeldWait(registered)

    async let outcome = changes.announceTestNotification()
    let reply = await held
    let id = try #require(Self.announcementID(reply))
    #expect(reply.revision == baseline)

    #expect(changes.reportTestNotification(id, outcome: .shown))
    #expect(await outcome == .shown)
    #expect(!changes.reportTestNotification(id, outcome: .denied))
  }

  @Test
  func anAnnouncementBetweenWaitsIsTakenByTheNextWait() async throws {
    let changes = ServiceStatusChanges(center: NotificationCenter())
    let baseline = await Self.revision(changes)
    async let outcome = changes.announceTestNotification()
    try await Task.sleep(nanoseconds: 20_000_000)

    let reply = await changes.wait(after: baseline, holdSeconds: 30)
    let id = try #require(Self.announcementID(reply))

    #expect(changes.reportTestNotification(id, outcome: .denied))
    #expect(await outcome == .denied)
  }

  @Test
  func aFailedReportCarriesTheReason() async throws {
    let changes = ServiceStatusChanges(center: NotificationCenter())
    async let outcome = changes.announceTestNotification()
    try await Task.sleep(nanoseconds: 20_000_000)
    let id = try #require(Self.announcementID(await changes.wait(after: nil, holdSeconds: 30)))

    #expect(changes.reportTestNotification(id, outcome: .failed("no delivery")))
    #expect(await outcome == .failed("no delivery"))
  }

  @Test
  func noWaitBeforeThePickupDeadlineEndsWithNoAnswer() async {
    let changes = ServiceStatusChanges(center: NotificationCenter(), pickupSeconds: 0.05)

    #expect(await changes.announceTestNotification() == .noAnswer)
    let reply = await changes.wait(after: nil, holdSeconds: 30)
    #expect(reply.event == .firstRead)
  }

  @Test
  func aTakenAnnouncementWithNoReportEndsWithNoAnswer() async throws {
    let changes = ServiceStatusChanges(center: NotificationCenter(), answerSeconds: 0.05)
    async let outcome = changes.announceTestNotification()
    try await Task.sleep(nanoseconds: 20_000_000)
    _ = try #require(Self.announcementID(await changes.wait(after: nil, holdSeconds: 30)))

    #expect(await outcome == .noAnswer)
  }

  @Test
  func aCancelledWaitEndsAsHoldElapsedAndDoesNotTakeTheAnnouncement() async {
    let changes = ServiceStatusChanges(center: NotificationCenter(), pickupSeconds: 0.05)
    let baseline = await Self.revision(changes)
    let cancelled = Task { await changes.wait(after: baseline, holdSeconds: 30) }
    cancelled.cancel()

    #expect(await cancelled.value.event == .holdElapsed)
    #expect(changes.heldWaitCount == 0)
    #expect(await changes.announceTestNotification() == .noAnswer)
  }

  @Test
  func aHeldWaitCancelledAsItTakesTheAnnouncementGivesItBackForTheNextWait() async throws {
    let changes = ServiceStatusChanges(center: NotificationCenter())
    let baseline = await Self.revision(changes)
    let registered = Self.heldWaits(changes)
    let held = Task { await changes.wait(after: baseline, holdSeconds: 30) }
    await Self.nextHeldWait(registered)
    changes.announcementWillReachWait = { held.cancel() }

    async let outcome = changes.announceTestNotification()

    #expect(await held.value.event == .holdElapsed)
    let id = try #require(Self.announcementID(await changes.wait(after: nil, holdSeconds: 30)))
    #expect(changes.reportTestNotification(id, outcome: .shown))
    #expect(await outcome == .shown)
  }

  @Test
  func anAnnouncementGivenBackAfterThePickupDeadlineExpiresInsteadOfReachingAHeldWait()
    async throws
  {
    let changes = ServiceStatusChanges(
      center: NotificationCenter(),
      pickupSeconds: 0.01,
      answerSeconds: 0.5
    )
    let baseline = await Self.revision(changes)
    let registered = Self.heldWaits(changes)
    let first = Task { await changes.wait(after: baseline, holdSeconds: 30) }
    await Self.nextHeldWait(registered)
    let secondRegistered = DispatchSemaphore(value: 0)
    let second = Locked<Task<ServiceStatusReply, Never>?>(nil)
    changes.heldWaitDidRegister = { secondRegistered.signal() }
    // The hook runs for each wait an announcement is handed to; only the first hand-over is set up.
    let handedOver = Locked(false)
    changes.announcementWillReachWait = {
      guard
        !handedOver.withLock({ value in
          defer { value = true }
          return value
        })
      else { return }
      first.cancel()
      second.withLock { $0 = Task { await changes.wait(after: baseline, holdSeconds: 30) } }
      _ = secondRegistered.wait(timeout: .now() + 10)
      // Lets the pickup deadline pass while the first wait still holds the announcement.
      Thread.sleep(forTimeInterval: 0.05)
    }

    let outcome = await changes.announceTestNotification()
    let secondWait = try #require(second.withLock { $0 })
    secondWait.cancel()

    #expect(await first.value.event == .holdElapsed)
    #expect(outcome == .noAnswer)
    #expect(await secondWait.value.event == .holdElapsed)
  }

  @Test
  func aRequestWhileOneIsPendingJoinsIt() async throws {
    let changes = ServiceStatusChanges(center: NotificationCenter())
    async let first = changes.announceTestNotification()
    try await Task.sleep(nanoseconds: 20_000_000)
    async let second = changes.announceTestNotification()
    try await Task.sleep(nanoseconds: 20_000_000)
    let id = try #require(Self.announcementID(await changes.wait(after: nil, holdSeconds: 30)))

    #expect(changes.reportTestNotification(id, outcome: .shown))
    #expect(await first == .shown)
    #expect(await second == .shown)
  }

  @Test
  func aReportForAnAnnouncementNobodyTookIsRefused() async throws {
    let changes = ServiceStatusChanges(center: NotificationCenter(), pickupSeconds: 0.2)

    #expect(!changes.reportTestNotification(UUID(), outcome: .shown))
    #expect(await changes.announceTestNotification() == .noAnswer)
  }

  @Test
  func aCallerThatLeavesAbandonsTheAnnouncementAndLaterReportsAreRefused() async throws {
    let changes = ServiceStatusChanges(center: NotificationCenter())
    let baseline = await Self.revision(changes)
    let caller = Task { await changes.announceTestNotification() }
    try await Task.sleep(nanoseconds: 20_000_000)
    let reply = await changes.wait(after: baseline, holdSeconds: 30)
    let id = try #require(Self.announcementID(reply))

    caller.cancel()

    #expect(await caller.value == nil)
    #expect(!changes.reportTestNotification(id, outcome: .shown))
  }

  @Test
  func aRequestKeepsTheAnnouncementWhileAnotherCallerStaysAfterOneLeaves() async throws {
    let changes = ServiceStatusChanges(center: NotificationCenter())
    let leaving = Task { await changes.announceTestNotification() }
    try await Task.sleep(nanoseconds: 20_000_000)
    async let staying = changes.announceTestNotification()
    try await Task.sleep(nanoseconds: 20_000_000)
    let id = try #require(Self.announcementID(await changes.wait(after: nil, holdSeconds: 30)))

    leaving.cancel()

    #expect(await leaving.value == nil)
    #expect(changes.reportTestNotification(id, outcome: .denied))
    #expect(await staying == .denied)
  }

  @Test
  func aStalePickupDeadlineCannotEndATakenAnnouncement() async throws {
    let changes = ServiceStatusChanges(center: NotificationCenter())
    async let outcome = changes.announceTestNotification()
    try await Task.sleep(nanoseconds: 20_000_000)
    let id = try #require(Self.announcementID(await changes.wait(after: nil, holdSeconds: 30)))

    changes.expire(id, token: UUID())

    #expect(changes.reportTestNotification(id, outcome: .shown))
    #expect(await outcome == .shown)
  }
}
