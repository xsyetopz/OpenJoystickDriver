import Foundation

/// Describes why a JSON document did not decode, naming the field. Foundation's own
/// description of a `DecodingError` names neither the field nor the reason.
enum DocumentProblem {
  static func describe(_ error: any Error) -> String {
    guard let error = error as? DecodingError else { return error.localizedDescription }
    switch error {
    case let .keyNotFound(key, context):
      return missing(context.codingPath + [key])
    case let .valueNotFound(_, context):
      return missing(context.codingPath)
    case let .typeMismatch(_, context):
      return CLILocalized.format(
        "cli.document.wrong_type",
        path(context.codingPath)
      )
    case let .dataCorrupted(context):
      // Only the JSON parser attaches an underlying error at the document root.
      if context.codingPath.isEmpty, context.underlyingError != nil {
        return CLILocalized.text("cli.document.not_json")
      }
      if context.codingPath.isEmpty { return context.debugDescription }
      return CLILocalized.format(
        "cli.document.field_problem",
        path(context.codingPath),
        context.debugDescription
      )
    @unknown default:
      return error.localizedDescription
    }
  }

  private static func missing(_ codingPath: [any CodingKey]) -> String {
    CLILocalized.format("cli.document.missing_field", path(codingPath))
  }

  /// A path such as `bindings[0].source`.
  static func path(_ codingPath: [any CodingKey]) -> String {
    codingPath.reduce(into: "") { text, key in
      if let index = key.intValue {
        text += "[\(index)]"
      } else {
        text += text.isEmpty ? key.stringValue : ".\(key.stringValue)"
      }
    }
  }
}
