import Foundation
import OpenJoystickDriverTestSupport

/// Validates `--json` output against `Resources/Schemas/v1beta1/cli-output.schema.json`.
///
/// Each command's output is the `$defs` entry named by its path in lowerCamelCase, such as
/// `controllerShow` for `ojd controller show`.
enum CLIOutputSchema {
  static let fileName = "cli-output.schema.json"
  static let profileFileName = "profile.schema.json"

  /// Commands whose stdout is not a `--json` document of their own.
  static let exempt: Set<[String]> = [
    // Prints the profile file for every format; `CLIRun` checks it against the profile schema.
    ["profile", "export"],
    // Opens an editor and needs a terminal, so tests never reach its output.
    ["profile", "edit"],
  ]

  static func definitionName(for path: [String]) -> String {
    path.enumerated().map { index, name in
      let words = name.split(separator: "-").map(String.init)
      return words.enumerated().map { offset, word in
        index == 0 && offset == 0 ? word : word.prefix(1).uppercased() + word.dropFirst()
      }.joined()
    }.joined()
  }

  static func document(named name: String = fileName) throws -> [String: Any] {
    try JSONSchemaFiles.document(named: name)
  }

  static var definitions: [String: Any] {
    ((try? document())?["$defs"] as? [String: Any]) ?? [:]
  }

  /// The issues in `output`, one JSON document or one document per line for a stream.
  static func issues(in output: String, path: [String]) throws -> [String] {
    let name = definitionName(for: path)
    guard definitions[name] != nil else { return ["\(fileName) has no $defs/\(name)"] }
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    let texts =
      (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8), options: .fragmentsAllowed))
        != nil ? [trimmed] : trimmed.split(separator: "\n").map(String.init)
    var issues: [String] = []
    let validator = JSONSchemaFiles.Validator()
    for text in texts {
      let value = try JSONSerialization.jsonObject(
        with: Data(text.utf8),
        options: .fragmentsAllowed
      )
      issues += try validator.validate(
        value,
        against: ["$ref": "#/$defs/\(name)"],
        in: fileName,
        at: "$"
      )
    }
    return issues
  }

  /// The issues in `text`, one profile file, against `profile.schema.json`.
  static func profileIssues(in text: String) throws -> [String] {
    let value = try JSONSerialization.jsonObject(with: Data(text.utf8))
    return try JSONSchemaFiles.Validator().validate(
      value,
      against: ["$ref": profileFileName],
      in: profileFileName,
      at: "$"
    )
  }
}
