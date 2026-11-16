import Foundation

/// Describes why a JSON document did not decode, naming the field.
///
/// Foundation's own description of a `DecodingError` names neither the field nor the reason.
public enum DocumentProblem {
  /// Localized message catalog of the document problems.
  private static let localization = Localization()

  /// Returns a localized sentence for a failed document decode.
  ///
  /// A document header problem gives its own message. A `DecodingError` names the field by its path
  /// and says whether it is missing, has the wrong type, or is not JSON at all. Any other error
  /// gives its localized description.
  public static func describe(_ error: any Error) -> String {
    if let problem = error as? DocumentHeaderProblem { return problem.message }
    guard let decoding = error as? DecodingError else { return error.localizedDescription }
    switch decoding {
    case .keyNotFound(let key, let context):
      return missing(context.codingPath + [key])
    case .valueNotFound(_, let context):
      return missing(context.codingPath)
    case .typeMismatch(_, let context):
      return localization.formatted(
        "cli.shared.document.wrongType",
        arguments: [path(context.codingPath)]
      )
    case .dataCorrupted(let context):
      // Only the JSON parser attaches an underlying error at the document root.
      if context.codingPath.isEmpty, context.underlyingError != nil {
        return localization.string("cli.shared.document.notJson")
      }
      if context.codingPath.isEmpty { return context.debugDescription }
      return localization.formatted(
        "cli.shared.document.fieldProblem",
        arguments: [path(context.codingPath), context.debugDescription]
      )
    @unknown default:
      return decoding.localizedDescription
    }
  }

  /// Message for a missing field at a coding path.
  private static func missing(_ codingPath: [any CodingKey]) -> String {
    localization.formatted("cli.shared.document.missingField", arguments: [path(codingPath)])
  }

  /// Joins a coding path into text such as `bindings[0].source`.
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
