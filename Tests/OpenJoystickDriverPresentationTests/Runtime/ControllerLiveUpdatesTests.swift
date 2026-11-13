import Foundation
import Testing

@testable import OpenJoystickDriverKit
@testable import OpenJoystickDriverPresentation

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct ControllerLiveUpdatesTests {
  private func makeUpdates(
    _ source: ScriptedChangeSource,
    refreshed: Counter,
    logged: LogLines = LogLines(),
    modes: Modes = Modes(),
    answeredTestNotifications: Answers = Answers()
  ) -> ControllerLiveUpdates {
    ControllerLiveUpdates(
      source: source,
      fallbackPollSeconds: 0.01,
      log: { logged.lines.append($0) },
      answerTestNotification: { answeredTestNotifications.ids.append($0) },
      modeChanged: { modes.values.append($0) },
      refresh: { refreshed.increment() }
    )
  }

  @Test
  func firstAnswerRefreshesOnceAndServiceNotificationRefreshesWithinOneSecond() async {
    let source = ScriptedChangeSource()
    let refreshed = Counter()
    let updates = makeUpdates(source, refreshed: refreshed)
    updates.start()
    defer { updates.stop() }
    source.answer(.revision(1))
    await refreshed.waitUntil(1, timeout: 30)
    #expect(updates.mode == .subscribed)
    #expect(refreshed.value == 1)

    source.answer(.revision(2))
    await refreshed.waitUntil(2, timeout: 30)

    #expect(refreshed.value == 2)
  }

  @Test
  func testNotificationAnnouncementIsAnsweredAndRefreshesNothing() async {
    let source = ScriptedChangeSource()
    let refreshed = Counter()
    let answers = Answers()
    let updates = makeUpdates(source, refreshed: refreshed, answeredTestNotifications: answers)
    updates.start()
    defer { updates.stop() }
    source.answer(.revision(1))
    await refreshed.waitUntil(1, timeout: 30)
    let id = UUID()

    source.answer(.revision(1), event: .testNotification, announcement: id)
    source.answer(.revision(2))
    await refreshed.waitUntil(2, timeout: 30)

    #expect(answers.ids == [id])
    #expect(refreshed.value == 2)
  }

  @Test
  func holdTimeAnswerWithNoChangeRefreshesNothing() async {
    let source = ScriptedChangeSource()
    let refreshed = Counter()
    let updates = makeUpdates(source, refreshed: refreshed)
    updates.start()
    defer { updates.stop() }
    source.answer(.revision(1))
    source.answer(.revision(1))
    source.answer(.revision(2))
    await refreshed.waitUntil(2, timeout: 30)

    #expect(refreshed.value == 2)
  }

  @Test
  func restartedServiceWithSameCountRefreshes() async {
    let source = ScriptedChangeSource()
    let refreshed = Counter()
    let updates = makeUpdates(source, refreshed: refreshed)
    updates.start()
    defer { updates.stop() }
    source.answer(.revision(0))
    await refreshed.waitUntil(1, timeout: 30)
    source.answer(.revision(0, instance: "00000000-0000-0000-0000-000000000002"))
    await refreshed.waitUntil(2, timeout: 30)

    #expect(refreshed.value == 2)
  }

  @Test
  func pollingIsLoggedOnceAndReportedOnlyAfterSeveralConsecutiveFailures() async {
    let source = ScriptedChangeSource()
    let refreshed = Counter()
    let logged = LogLines()
    let modes = Modes()
    let updates = makeUpdates(source, refreshed: refreshed, logged: logged, modes: modes)
    updates.start()
    defer { updates.stop() }

    for _ in 0..<(ControllerLiveUpdates.failuresBeforeReporting - 1) {
      source.fail(ScriptedFailure.unreachable)
    }
    await refreshed.waitUntil(ControllerLiveUpdates.failuresBeforeReporting - 1, timeout: 30)
    #expect(modes.values.isEmpty)
    #expect(logged.lines.count == 1)
    #expect(logged.lines.first?.contains("polling every 0.01 s") == true)
    #expect(logged.lines.first?.contains("The service is unreachable.") == true)

    source.fail(ScriptedFailure.unreachable)
    await refreshed.waitUntil(ControllerLiveUpdates.failuresBeforeReporting, timeout: 30)

    let expected = ControllerLiveUpdateMode.polling(
      failure: .other,
      detail: ScriptedFailure.unreachable.localizedDescription
    )
    #expect(updates.mode == expected)
    #expect(modes.values == [expected])
    #expect(logged.lines.count == 1)
  }

  @Test
  func failureWithChangingTextOfSameKindIsReportedOnce() async {
    let source = ScriptedChangeSource()
    let refreshed = Counter()
    let modes = Modes()
    let updates = makeUpdates(source, refreshed: refreshed, modes: modes)
    updates.start()
    defer { updates.stop() }
    for _ in 0..<ControllerLiveUpdates.failuresBeforeReporting {
      source.fail(ScriptedFailure.unreachable)
    }
    await refreshed.waitUntil(ControllerLiveUpdates.failuresBeforeReporting, timeout: 30)
    source.fail(ScriptedFailure.other("first"))
    source.fail(ScriptedFailure.other("second"))
    await refreshed.waitUntil(ControllerLiveUpdates.failuresBeforeReporting + 2, timeout: 30)

    #expect(modes.values.count == 1)

    source.fail(ApplicationServiceClientError.timeout)
    await refreshed.waitUntil(ControllerLiveUpdates.failuresBeforeReporting + 3, timeout: 30)

    #expect(modes.values.count == 2)
  }

  @Test
  func recoveryBeforeThresholdNeverReportsPolling() async {
    let source = ScriptedChangeSource()
    let refreshed = Counter()
    let logged = LogLines()
    let modes = Modes()
    let updates = makeUpdates(source, refreshed: refreshed, logged: logged, modes: modes)
    updates.start()
    defer { updates.stop() }
    source.fail(ScriptedFailure.unreachable)
    await refreshed.waitUntil(1, timeout: 30)
    source.answer(.revision(5))
    await refreshed.waitUntil(2, timeout: 30)

    #expect(updates.mode == .subscribed)
    #expect(modes.values.isEmpty)
    #expect(logged.lines.count == 2)
  }

  @Test
  func restoredWaitAfterReportedFallbackIsReportedOnceAndRefreshes() async {
    let source = ScriptedChangeSource()
    let refreshed = Counter()
    let modes = Modes()
    let updates = makeUpdates(source, refreshed: refreshed, modes: modes)
    updates.start()
    defer { updates.stop() }
    for _ in 0..<ControllerLiveUpdates.failuresBeforeReporting {
      source.fail(ScriptedFailure.unreachable)
    }
    await refreshed.waitUntil(ControllerLiveUpdates.failuresBeforeReporting, timeout: 30)

    source.answer(.revision(5))
    await refreshed.waitUntil(ControllerLiveUpdates.failuresBeforeReporting + 1, timeout: 30)

    #expect(updates.mode == .subscribed)
    #expect(modes.values.last == .subscribed)
    #expect(modes.values.count == 2)
  }

  @Test
  func failuresMapToOneBannerReasonEach() {
    #expect(
      ControllerLiveUpdateFailure(LocalServiceRPCError.serviceClosedConnection)
        == .serviceClosedConnection
    )
    #expect(ControllerLiveUpdateFailure(ApplicationServiceClientError.timeout) == .timeout)
    #expect(ControllerLiveUpdateFailure(ScriptedFailure.unreachable) == .other)
    let keys = [
      ControllerLiveUpdateFailure.serviceClosedConnection, .timeout, .other,
    ].map(\.detailKey)
    #expect(Set(keys).count == 3)
    for key in keys { #expect(OJDLocalized.string(key) != key) }
  }
}

private enum ScriptedFailure: Error, LocalizedError {
  case unreachable
  case other(String)
  var errorDescription: String? {
    switch self {
    case .unreachable: return "The service is unreachable."
    case .other(let text): return text
    }
  }
}

@MainActor
private final class Counter {
  private(set) var value = 0
  func increment() { value += 1 }

  func waitUntil(_ target: Int, timeout: Double) async {
    let deadline = Date().addingTimeInterval(timeout)
    while value < target, Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
  }
}

@MainActor
private final class Answers { var ids: [UUID] = [] }

@MainActor
private final class LogLines { var lines: [String] = [] }

@MainActor
private final class Modes { var values: [ControllerLiveUpdateMode] = [] }

extension ServiceStatusRevision {
  static func revision(
    _ generation: UInt64,
    instance: String = "00000000-0000-0000-0000-000000000001"
  ) -> Self {
    Self(instance: UUID(uuidString: instance)!, generation: generation)
  }
}

/// A change source whose waits finish only when the test answers or fails them.
private final class ScriptedChangeSource: ControllerChangeSource, @unchecked Sendable {
  private let lock = NSLock()
  private var pending: [CheckedContinuation<ServiceStatusReply, any Error>] = []
  private var queued: [Result<ServiceStatusReply, any Error>] = []

  func waitForChange(after _: ServiceStatusRevision?) async throws -> ServiceStatusReply {
    try await withCheckedThrowingContinuation { continuation in
      let ready = lock.withLock { () -> Result<ServiceStatusReply, any Error>? in
        if queued.isEmpty {
          pending.append(continuation)
          return nil
        }
        return queued.removeFirst()
      }
      if let ready { continuation.resume(with: ready) }
    }
  }

  func answer(
    _ revision: ServiceStatusRevision,
    event: ServiceStatusEventKind = .statusChange,
    announcement: UUID? = nil
  ) {
    deliver(
      .success(ServiceStatusReply(revision: revision, event: event, announcement: announcement))
    )
  }
  func fail(_ error: any Error) { deliver(.failure(error)) }

  private func deliver(_ result: Result<ServiceStatusReply, any Error>) {
    let waiting = lock.withLock { () -> CheckedContinuation<ServiceStatusReply, any Error>? in
      if pending.isEmpty {
        queued.append(result)
        return nil
      }
      return pending.removeFirst()
    }
    waiting?.resume(with: result)
  }
}
