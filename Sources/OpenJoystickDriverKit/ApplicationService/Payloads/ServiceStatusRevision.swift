public import Foundation

/// Which service process answered `waitForServiceStatusChange` and how many status changes it has
/// recorded.
///
/// A status change is any change to what `getStatus` or the remapping snapshot reports:
/// controller attach, detach and session state, permissions, the virtual device backend, input
/// connection and recovery, and profile state. A caller compares whole revisions, so a restarted
/// service, whose count starts at 0 again, differs from the one the caller last saw.
public struct ServiceStatusRevision: Codable, Equatable, Sendable {
  /// Seconds the service holds a wait with no change before it replies with the same revision.
  public static let holdSeconds: TimeInterval = 20

  /// Identifies the service process; fixed for its lifetime.
  public let instance: UUID
  /// Status changes recorded since that process started.
  public let generation: UInt64

  /// Creates a revision from the service process `instance` and its `generation`.
  public init(instance: UUID, generation: UInt64) {
    self.instance = instance
    self.generation = generation
  }
}

/// Arguments of `waitForServiceStatusChange`: the revision the caller last saw, or nil to read
/// the current one at once.
public struct LocalServiceRPCStatusChangeArguments: Codable, Sendable {
  /// The revision the caller last saw; nil reads the current revision at once.
  public let after: ServiceStatusRevision?

  /// Creates the arguments from the revision the caller last saw.
  public init(after: ServiceStatusRevision?) { self.after = after }
}

/// Why the service answered a `waitForServiceStatusChange`.
public enum ServiceStatusEventKind: String, Codable, Equatable, Sendable {
  /// The caller sent no revision, so this is the current one read at once.
  case firstRead
  /// The revision differs from the one the caller sent, or a status change moved it.
  case statusChange
  /// The hold time passed with no change, or the caller's wait was cancelled; the revision is
  /// the current one.
  case holdElapsed
  /// A client asked the app to show its test notification, and this wait took the announcement.
  /// The status did not change. The reply carries the announcement's identifier.
  case testNotification
}

/// The service's reply to `waitForServiceStatusChange`: the current revision, why the service
/// answered now, and for a test notification the announcement the caller answers with
/// `reportTestNotificationResult`.
public struct ServiceStatusReply: Codable, Equatable, Sendable {
  /// The service's current revision.
  public let revision: ServiceStatusRevision
  /// Why the service answered now.
  public let event: ServiceStatusEventKind
  /// Present exactly when `event` is `testNotification`.
  public let announcement: UUID?

  /// Creates a reply; `announcement` belongs to the `testNotification` event alone.
  public init(
    revision: ServiceStatusRevision,
    event: ServiceStatusEventKind,
    announcement: UUID? = nil
  ) {
    self.revision = revision
    self.event = event
    self.announcement = announcement
  }

  /// Decodes the value from `decoder`.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    revision = try container.decode(ServiceStatusRevision.self, forKey: .revision)
    event = try container.decode(ServiceStatusEventKind.self, forKey: .event)
    announcement = try container.decodeIfPresent(UUID.self, forKey: .announcement)
    guard (event == .testNotification) == (announcement != nil) else {
      throw DecodingError.dataCorruptedError(
        forKey: .announcement,
        in: container,
        debugDescription: "An announcement belongs to the testNotification event alone."
      )
    }
  }
}

/// How a test notification ended.
///
/// The app reports `shown`, `denied` or `failed`; the service itself decides `noAnswer`. On the
/// wire it is `{"kind": ...}`, with `reason` beside `failed` alone.
public enum TestNotificationOutcome: Codable, Equatable, Sendable {
  /// The app delivered the notification.
  case shown
  /// Notifications are not allowed for the app.
  case denied
  /// The app tried and the system reported an error; the associated value is its text.
  case failed(String)
  /// No app took the announcement before `TestNotificationDeadlines.pickupSeconds`, or the app
  /// that took it did not report within `TestNotificationDeadlines.answerSeconds`.
  case noAnswer

  /// The keys of the JSON encoding.
  private enum CodingKeys: String, CodingKey {
    /// The `kind` key.
    case kind
    /// The `reason` key.
    case reason
  }
  /// The `kind` value on the wire.
  private enum Kind: String, Codable {
    /// The notification was shown.
    case shown
    /// Notifications are not allowed for the app.
    case denied
    /// The app reported an error.
    case failed
    /// No app answered in time.
    case noAnswer
  }

  /// Decodes the value from `decoder`.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let reason = try container.decodeIfPresent(String.self, forKey: .reason)
    let kind = try container.decode(Kind.self, forKey: .kind)
    guard (kind == .failed) == (reason != nil) else {
      throw DecodingError.dataCorruptedError(
        forKey: .reason,
        in: container,
        debugDescription: "A reason belongs to a failed outcome alone."
      )
    }
    switch kind {
    case .shown: self = .shown
    case .denied: self = .denied
    case .noAnswer: self = .noAnswer
    case .failed: self = .failed(reason ?? "")
    }
  }

  /// Encodes the value into `encoder`.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .shown: try container.encode(Kind.shown, forKey: .kind)
    case .denied: try container.encode(Kind.denied, forKey: .kind)
    case .noAnswer: try container.encode(Kind.noAnswer, forKey: .kind)
    case .failed(let reason):
      try container.encode(Kind.failed, forKey: .kind)
      try container.encode(reason, forKey: .reason)
    }
  }
}

/// How long the service waits on a test notification.
///
/// A request that has no answer by then ends with `TestNotificationOutcome.noAnswer`. With
/// several apps connected, the first wait to reach the service takes the announcement and that
/// app alone answers; the others see nothing.
public enum TestNotificationDeadlines {
  /// From the request until a wait takes the announcement.
  ///
  /// An app re-arms its wait within a second, so a longer gap means no app is connected.
  public static let pickupSeconds: TimeInterval = 3
  /// From the pickup until the app reports.
  ///
  /// It covers the system prompt that asks permission, which the user may leave open for a while.
  public static let answerSeconds: TimeInterval = 30
}

/// Arguments of `reportTestNotificationResult`: the announcement being answered and how it ended.
///
/// The outcome is `shown`, `denied` or `failed`.
public struct TestNotificationReport: Codable, Equatable, Sendable {
  /// The announcement that the app answers.
  public let announcement: UUID
  /// How the test notification ended.
  public let outcome: TestNotificationOutcome

  /// Creates the report from an announcement and its outcome.
  public init(announcement: UUID, outcome: TestNotificationOutcome) {
    self.announcement = announcement
    self.outcome = outcome
  }
}
