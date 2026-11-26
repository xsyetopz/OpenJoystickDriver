import Foundation

/// Why a protocol description is invalid, in words for the person who wrote it, with the
/// catalog code that names the failure.
public struct ProtocolDescriptionProblem: Error, Equatable, Sendable, CustomStringConvertible {
  /// The error code of the rejection.
  public let code: ErrorCode
  /// What the description got wrong.
  public let detail: String

  /// Creates a problem from an error code and the detail.
  init(_ code: ErrorCode, _ detail: String) {
    self.code = code
    self.detail = detail
  }

  /// The raw value of the code and the detail, joined by a colon.
  public var description: String { "\(code.rawValue): \(detail)" }
}
