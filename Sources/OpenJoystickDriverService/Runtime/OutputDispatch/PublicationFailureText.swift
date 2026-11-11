import Foundation

/// The text of a failed publication.
///
/// A failed publication always carries text, so an error whose description is empty or blank is
/// named by its type, domain and code.
enum PublicationFailureText {
  /// Returns the text of `error`, or its type, domain and code when the description is blank.
  static func text(for error: any Error) -> String {
    let description = String(describing: error)
    guard description.allSatisfy(\.isWhitespace) else { return description }
    let bridged = error as NSError
    return "\(type(of: error)) (\(bridged.domain) \(bridged.code))"
  }
}
