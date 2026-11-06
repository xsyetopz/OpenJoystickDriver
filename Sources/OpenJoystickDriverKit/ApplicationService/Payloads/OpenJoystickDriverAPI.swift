import Foundation

/// The `apiVersion` of every JSON document and line that `ojd --json` prints, that the endpoint
/// speaks, and that OJD reads or writes as a file.
public enum OpenJoystickDriverAPI {
  /// The supported `apiVersion`.
  public static let version = "openjoystickdriver/v1alpha2"

  /// The start of the `$id` of every JSON Schema under `Resources/Schemas`; the file name follows.
  public static let schemaBase = "https://xsyetopz.github.io/OpenJoystickDriver/schemas/v1alpha2/"

  /// Why a document with this `apiVersion` and `kind` is not a supported `expected`, or nil when
  /// it is.
  ///
  /// OJD does not upgrade a document of another version: the problem names what it found and what
  /// it supports. A missing or unknown `apiVersion` carries ``ErrorCode/unsupportedAPIVersion``;
  /// a wrong `kind` carries no code.
  public static func headerProblem(
    apiVersion: Any?,
    kind: Any?,
    expected: String
  ) -> DocumentHeaderProblem? {
    guard let apiVersion else {
      return DocumentHeaderProblem(
        code: .unsupportedAPIVersion,
        "no apiVersion found; the supported apiVersion is \(version)"
      )
    }
    guard (apiVersion as? String) == version else {
      return DocumentHeaderProblem(
        code: .unsupportedAPIVersion,
        "apiVersion \(apiVersion) is not supported; the supported apiVersion is \(version)"
      )
    }
    guard let kind else {
      return DocumentHeaderProblem(code: nil, "no kind found; expected \(expected)")
    }
    guard (kind as? String) == expected else {
      return DocumentHeaderProblem(code: nil, "expected \(expected), found \(kind)")
    }
    return nil
  }

  /// Requires the `apiVersion` and `kind` read from a document to be the supported `apiVersion`
  /// and the `kind` it is read as.
  ///
  /// A `file` name leads the reason. A value that is not a string is reported as written.
  static func requireHeader(
    apiVersion: OrderedJSON?,
    kind: OrderedJSON?,
    expected: String,
    file: String? = nil
  ) throws {
    func text(_ value: OrderedJSON?) -> Any? { value.map { $0.string ?? $0.compact() } }
    guard
      let problem = headerProblem(
        apiVersion: text(apiVersion),
        kind: text(kind),
        expected: expected
      )
    else { return }
    throw file.map { problem.located(in: $0) } ?? problem
  }
}

/// Why a document's `apiVersion` or `kind` is not the supported one.
///
/// `code` is ``ErrorCode/unsupportedAPIVersion`` when the `apiVersion` is missing or unknown, and
/// nil when only the `kind` is wrong. `message` names the file when there is one, the version
/// found, and the supported one. `description` leads with the code, as ``ModPackageError`` does.
public struct DocumentHeaderProblem: Error, Equatable, Sendable, CustomStringConvertible,
  LocalizedError
{
  /// The error code; nil when only the `kind` is wrong.
  public let code: ErrorCode?
  /// The description of the problem.
  public let message: String

  /// Creates a problem from a code and a message.
  init(code: ErrorCode?, _ message: String) {
    self.code = code
    self.message = message
  }

  /// The same problem, with `file` leading the message.
  func located(in file: String) -> Self { Self(code: code, "\(file): \(message)") }

  /// The problem as text: the code, when there is one, then the message.
  public var description: String { (code.map { "\($0.rawValue): " } ?? "") + message }
  /// The description of the error for the user.
  public var errorDescription: String? { description }
}
