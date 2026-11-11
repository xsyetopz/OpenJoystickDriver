import Foundation

/// What the helper process writes on standard output: the result of the script, or why it has none.
enum GenerateReport: Codable, Equatable {
  /// `JSON.stringify` of what `generate` returned, or nil when that is not a JSON value.
  case result(String?)
  /// The script defines no `generate` function.
  case missingGenerate
  /// The script has a syntax error or threw; `line` is nil when the thrown value has none.
  case failure(message: String, line: Int?)
}
