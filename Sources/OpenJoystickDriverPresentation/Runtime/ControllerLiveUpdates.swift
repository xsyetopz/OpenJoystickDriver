import Foundation
import OpenJoystickDriverKit

/// Waits on the service for status changes and the events it announces to the app.
protocol ControllerChangeSource: Sendable {
  /// Returns the service's reply once its status revision differs from `revision`, after the
  /// service's hold time with the same one, or when the service announces an event. A nil
  /// `revision` returns the current one at once.
  func waitForChange(after revision: ServiceStatusRevision?) async throws -> ServiceStatusReply
}

/// Why the wait for service status changes failed, as the banner states it.
enum ControllerLiveUpdateFailure: Equatable, Sendable {
  /// The service closed the connection.
  case serviceClosedConnection
  /// The wait timed out.
  case timeout
  /// Any other error.
  case other

  /// Creates the failure for an error.
  init(_ error: any Error) {
    switch error {
    case LocalServiceRPCError.serviceClosedConnection: self = .serviceClosedConnection
    case ApplicationServiceClientError.timeout, LocalServiceRPCError.timeout: self = .timeout
    default: self = .other
    }
  }

  /// Localization key of the banner detail.
  var detailKey: String {
    switch self {
    case .serviceClosedConnection: return "ui.banner.liveUpdates.detail.closed"
    case .timeout: return "ui.banner.liveUpdates.detail.timeout"
    case .other: return "ui.banner.liveUpdates.detail.other"
    }
  }
}

/// How the app learns of service status changes.
enum ControllerLiveUpdateMode: Equatable {
  /// No wait has answered yet.
  case starting
  /// A wait is open on the service, which answers it when the status changes.
  case subscribed
  /// The wait is unavailable; the app reads the service every
  /// `ControllerLiveUpdates.fallbackPollSeconds` and tries the wait again on each read. `detail`
  /// is the error's own text, for the log only.
  case polling(failure: ControllerLiveUpdateFailure, detail: String)
}

/// Keeps the Controllers list, detail, Access, status item and menu current from service
/// notifications.
///
/// One wait is open on the service at a time. A first answer is the baseline and a changed
/// revision, including a different service instance, is a change; each refreshes. The service
/// announces every status change, including input reports that are overdue, so a held wait that
/// ends with no change refreshes nothing. When the wait fails, the mode becomes `.polling`, the
/// error is logged once, and `refresh` runs every `fallbackPollSeconds` until a wait succeeds
/// again. `modeChanged` reports polling only after `failuresBeforeReporting` consecutive
/// failures, so a service restart does not flash a banner, reports again only when the failure
/// kind changes, and reports the restored wait.
///
/// A reply that carries a test-notification announcement calls `answerTestNotification` and
/// refreshes nothing, because the status did not change.
@MainActor
final class ControllerLiveUpdates {
  /// The default seconds between reads while polling.
  static let fallbackPollSeconds: Double = 1
  /// How many consecutive failures pass before ``modeChanged`` reports polling.
  static let failuresBeforeReporting = 3

  /// How the app learns of status changes.
  private(set) var mode = ControllerLiveUpdateMode.starting
  /// Waits on the service for changes.
  private let source: any ControllerChangeSource
  /// Reads the service and updates the views.
  private let refresh: @MainActor () async -> Void
  /// Writes a log line.
  private let log: @MainActor (String) -> Void
  /// Called with the announcement of a test notification that a reply carries.
  private let answerTestNotification: @MainActor (UUID) -> Void
  /// Called when the mode is reported: polling after enough failures, and the restored wait.
  private let modeChanged: @MainActor (ControllerLiveUpdateMode) -> Void
  /// The seconds between reads while polling.
  private let fallbackPollSeconds: Double
  /// The task that runs the wait loop, or nil while stopped.
  private var task: Task<Void, Never>?
  /// How many waits failed in a row.
  private var consecutiveFailures = 0
  /// The kind of failure that ``modeChanged`` last reported, or nil.
  private var reportedFailure: ControllerLiveUpdateFailure?

  /// Creates the updates on a source of changes.
  init(
    source: any ControllerChangeSource,
    fallbackPollSeconds: Double = ControllerLiveUpdates.fallbackPollSeconds,
    log: @escaping @MainActor (String) -> Void = { print($0) },
    answerTestNotification: @escaping @MainActor (UUID) -> Void,
    modeChanged: @escaping @MainActor (ControllerLiveUpdateMode) -> Void,
    refresh: @escaping @MainActor () async -> Void
  ) {
    self.source = source
    self.refresh = refresh
    self.log = log
    self.answerTestNotification = answerTestNotification
    self.modeChanged = modeChanged
    self.fallbackPollSeconds = fallbackPollSeconds
  }

  /// Starts the wait loop; does nothing while it runs.
  func start() {
    guard task == nil else { return }
    task = Task { @MainActor [weak self] in await self?.run() }
  }

  /// Stops the wait loop.
  func stop() {
    task?.cancel()
    task = nil
  }

  /// Waits for changes until cancelled, refreshing after each change and after each failed wait.
  private func run() async {
    var revision: ServiceStatusRevision?
    while !Task.isCancelled {
      do {
        let reply = try await source.waitForChange(after: revision)
        if Task.isCancelled { return }
        recordSuccess()
        let changed = reply.revision != revision
        revision = reply.revision
        if let announcement = reply.announcement { answerTestNotification(announcement) }
        if changed { await refresh() }
      } catch {
        if Task.isCancelled { return }
        recordFailure(error)
        revision = nil
        await refresh()
        try? await Task.sleep(nanoseconds: UInt64(fallbackPollSeconds * 1_000_000_000))
      }
    }
  }

  /// Records a wait that succeeded: polling ends and the restored wait is reported when polling had
  /// been reported.
  private func recordSuccess() {
    if case .polling = mode {
      log("[ControllerLiveUpdates] Service subscription restored; polling stopped.")
    }
    consecutiveFailures = 0
    mode = .subscribed
    if reportedFailure != nil {
      reportedFailure = nil
      modeChanged(.subscribed)
    }
  }

  /// Records a failed wait: the mode becomes polling, the first failure is logged, and polling is
  /// reported after ``failuresBeforeReporting`` failures in a row and again when the kind changes.
  private func recordFailure(_ error: any Error) {
    consecutiveFailures += 1
    let failure = ControllerLiveUpdateFailure(error)
    let next = ControllerLiveUpdateMode.polling(
      failure: failure,
      detail: error.localizedDescription
    )
    if mode != next {
      if case .polling = mode {
      } else {
        log(
          "[ControllerLiveUpdates] Service subscription unavailable "
            + "(\(error.localizedDescription)); polling every \(fallbackPollSeconds) s."
        )
      }
      mode = next
    }
    if consecutiveFailures >= Self.failuresBeforeReporting, reportedFailure != failure {
      reportedFailure = failure
      modeChanged(next)
    }
  }
}

extension ApplicationServiceClientGateway: ControllerChangeSource {
  /// Waits for the service to report a status change or announce an event.
  ///
  /// - Parameter revision: The revision the caller has; nil returns the current one at once.
  /// - Returns: The service's reply.
  /// - Throws: The error of the request.
  func waitForChange(
    after revision: ServiceStatusRevision?
  ) async throws -> ServiceStatusReply {
    await ensureConnection()
    return try await client.waitForServiceStatusChange(after: revision)
  }
}
