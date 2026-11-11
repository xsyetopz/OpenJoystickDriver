import Foundation
import OpenJoystickDriverKit

/// What Explain Error Code shows for typed text.
///
/// The lookup is the one `ojd explain` does: the text, upper-cased, names an ``ErrorCode``, and its
/// facts are the answer.
enum ErrorCodeExplanation: Equatable {
  /// The text names a known code; the value holds its facts.
  case explained(ErrorCodeFacts)
  /// The text names no known code; the value is the text.
  case unknown(String)

  /// The answer for `text`, or nil while the text is blank.
  static func lookup(_ text: String) -> Self? {
    let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !typed.isEmpty else { return nil }
    guard let code = ErrorCode(typed: typed) else { return .unknown(typed) }
    return .explained(code.facts)
  }
}
