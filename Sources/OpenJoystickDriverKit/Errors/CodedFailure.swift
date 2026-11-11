import Foundation

/// An expected failure with a stable error code and a localized message.
///
/// `ojd`, the endpoint, and the App Intents run the same code, so each reports a refusal with the
/// same code.
public struct CodedFailure: Error, Equatable, Sendable {
  /// The stable error code.
  public let id: ErrorCode
  /// The localized text that states what failed and how to fix it.
  public let message: String

  /// Creates the failure from its code and message.
  public init(_ id: ErrorCode, _ message: String) {
    self.id = id
    self.message = message
  }

  /// A wrong command or request, with the usage code; `message` is the explanation.
  public static func usage(_ message: String) -> Self { Self(.usage, message) }
}

extension CodedFailure: LocalizedError {
  /// The message, so a caller that prints `localizedDescription` shows the text.
  public var errorDescription: String? { message }
}
