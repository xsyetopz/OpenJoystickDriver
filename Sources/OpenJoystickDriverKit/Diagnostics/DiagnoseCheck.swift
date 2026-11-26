import Foundation

/// The outcome of one `ojd diagnose` check.
///
/// The raw values are stable identifiers.
public enum DiagnoseStatus: String, Encodable, Equatable, Sendable {
  /// The check passed.
  case pass = "Pass"
  /// The check found something to review.
  case warn = "Warn"
  /// The check found a failure.
  case fail = "Fail"
  /// The check did not run; `detail` says why.
  case skip = "Skip"
}

/// One `ojd diagnose` check: a stable kebab-case `id`, its `status`, and a one-line `detail`.
public struct DiagnoseCheck: Encodable, Equatable, Sendable {
  /// The stable kebab-case ID of the check.
  public let id: String
  /// The outcome of the check.
  public let status: DiagnoseStatus
  /// The one-line explanation of the outcome.
  public let detail: String

  /// Creates a check from its `id`, `status` and `detail`.
  public init(_ id: String, _ status: DiagnoseStatus, _ detail: String) {
    self.id = id
    self.status = status
    self.detail = detail
  }
}
