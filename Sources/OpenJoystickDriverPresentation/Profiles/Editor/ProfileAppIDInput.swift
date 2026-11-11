import Foundation

/// The app ID field of a profile: one or more bundle identifiers separated by commas or spaces.
enum ProfileAppIDInput {
  /// The identifiers in `text`, in order.
  static func parse(_ text: String) -> [String] {
    text.split { $0 == "," || $0.isWhitespace }.map(String.init)
  }

  /// The field text for `identifiers`.
  static func text(_ identifiers: [String]) -> String { identifiers.joined(separator: ", ") }
}
