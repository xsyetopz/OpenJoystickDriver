import Foundation

/// Validates `--json` output against `Resources/Schemas/cli-output.schema.json`.
///
/// Each command's output is the `$defs` entry named by its path in lowerCamelCase, such as
/// `controllerShow` for `ojd controller show`. The validator implements the Draft 2020-12
/// keywords the schema family uses and reports any other keyword, so the check is never
/// silently weaker than the schema.
enum CLIOutputSchema {
  static let fileName = "cli-output.schema.json"
  static let profileFileName = "profile.schema.json"

  static let directory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // Support
    .deletingLastPathComponent()  // OpenJoystickDriverCLITests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()
    .appendingPathComponent("Resources/Schemas", isDirectory: true)

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
    let data = try Data(contentsOf: directory.appendingPathComponent(name))
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw SchemaError("\(name) is not a JSON object")
    }
    return object
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
    let validator = Validator()
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
    return try Validator().validate(
      value,
      against: ["$ref": profileFileName],
      in: profileFileName,
      at: "$"
    )
  }

  struct SchemaError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
  }

  private final class Validator {
    private var documents: [String: [String: Any]] = [:]

    private static let annotations: Set<String> = [
      "$schema", "$id", "$defs", "$comment", "title", "description", "examples", "default",
      "format",
    ]

    func validate(
      _ value: Any,
      against schema: Any,
      in file: String,
      at path: String
    ) throws
      -> [String]
    {
      if let allowed = schema as? Bool { return allowed ? [] : ["\(path): no value is allowed"] }
      guard let schema = schema as? [String: Any] else {
        throw SchemaError("\(file): a schema at \(path) is not an object")
      }
      var issues: [String] = []
      for (keyword, argument) in schema {
        if Self.annotations.contains(keyword) || keyword == "then" || keyword == "else" { continue }
        issues += try check(keyword, argument, schema: schema, value, in: file, at: path)
      }
      return issues
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func check(
      _ keyword: String,
      _ argument: Any,
      schema: [String: Any],
      _ value: Any,
      in file: String,
      at path: String
    ) throws -> [String] {
      switch keyword {
      case "$ref":
        let (target, targetFile) = try resolve(argument as? String ?? "", from: file)
        return try validate(value, against: target, in: targetFile, at: path)
      case "type":
        let types = (argument as? [String]) ?? [argument as? String ?? ""]
        return types.contains { Self.matches(value, type: $0) }
          ? [] : ["\(path): expected \(types.joined(separator: " or ")), got \(value)"]
      case "enum":
        let options = argument as? [Any] ?? []
        return options.contains { Self.equal($0, value) }
          ? [] : ["\(path): \(value) is not in \(options)"]
      case "const":
        return Self.equal(argument, value) ? [] : ["\(path): expected \(argument), got \(value)"]
      case "properties", "additionalProperties", "required", "propertyNames", "minProperties":
        guard let object = value as? [String: Any] else { return [] }
        return try checkObject(keyword, argument, schema: schema, object, in: file, at: path)
      case "prefixItems", "items", "minItems", "maxItems", "uniqueItems":
        guard let array = value as? [Any] else { return [] }
        return try checkArray(keyword, argument, schema: schema, array, in: file, at: path)
      case "minLength", "maxLength", "pattern":
        guard let string = value as? String else { return [] }
        return Self.checkString(keyword, argument, string, at: path)
      case "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum":
        guard let number = Self.number(value), let limit = Self.number(argument) else { return [] }
        let passes =
          switch keyword {
          case "minimum": number >= limit
          case "maximum": number <= limit
          case "exclusiveMinimum": number > limit
          default: number < limit
          }
        return passes ? [] : ["\(path): \(number) fails \(keyword) \(limit)"]
      case "oneOf", "anyOf", "allOf":
        let results = try (argument as? [Any] ?? []).map {
          try validate(value, against: $0, in: file, at: path)
        }
        let passing = results.filter(\.isEmpty).count
        switch keyword {
        case "allOf": return results.flatMap { $0 }
        case "anyOf": return passing > 0 ? [] : ["\(path): matches no anyOf branch: \(results)"]
        default:
          return passing == 1 ? [] : ["\(path): matches \(passing) oneOf branches: \(results)"]
        }
      case "if":
        let branch =
          try validate(value, against: argument, in: file, at: path).isEmpty
          ? schema["then"] : schema["else"]
        return try branch.map { try validate(value, against: $0, in: file, at: path) } ?? []
      case "not":
        return try validate(value, against: argument, in: file, at: path).isEmpty
          ? ["\(path): matches a not schema"] : []
      default:
        throw SchemaError("\(file): the test validator does not implement \(keyword)")
      }
    }

    private func checkObject(
      _ keyword: String,
      _ argument: Any,
      schema: [String: Any],
      _ object: [String: Any],
      in file: String,
      at path: String
    ) throws -> [String] {
      switch keyword {
      case "properties":
        let properties = argument as? [String: Any] ?? [:]
        return try object.keys.sorted().flatMap { key -> [String] in
          guard let property = properties[key], let member = object[key] else { return [] }
          return try validate(member, against: property, in: file, at: "\(path).\(key)")
        }
      case "additionalProperties":
        let known = Set((schema["properties"] as? [String: Any] ?? [:]).keys)
        return try object.keys.sorted().filter { !known.contains($0) }.flatMap { key in
          try validate(object[key] as Any, against: argument, in: file, at: "\(path).\(key)")
        }
      case "required":
        return (argument as? [String] ?? []).filter { object[$0] == nil }.map {
          "\(path): missing \($0)"
        }
      case "minProperties":
        return object.count >= (argument as? Int ?? 0) ? [] : ["\(path): too few properties"]
      default:
        return try object.keys.sorted().flatMap {
          try validate($0, against: argument, in: file, at: "\(path) key \($0)")
        }
      }
    }

    private func checkArray(
      _ keyword: String,
      _ argument: Any,
      schema: [String: Any],
      _ array: [Any],
      in file: String,
      at path: String
    ) throws -> [String] {
      switch keyword {
      case "prefixItems":
        return try zip(array.indices, argument as? [Any] ?? []).flatMap { index, item in
          try validate(array[index], against: item, in: file, at: "\(path)[\(index)]")
        }
      case "items":
        // `items` applies only to the elements after `prefixItems`.
        let start = (schema["prefixItems"] as? [Any])?.count ?? 0
        return try array.enumerated().dropFirst(start).flatMap { index, element in
          try validate(element, against: argument, in: file, at: "\(path)[\(index)]")
        }
      case "minItems":
        return array.count >= (argument as? Int ?? 0) ? [] : ["\(path): too few items"]
      case "maxItems":
        return array.count <= (argument as? Int ?? .max) ? [] : ["\(path): too many items"]
      default:
        guard argument as? Bool == true else { return [] }
        let unique = array.enumerated().allSatisfy { index, element in
          !array[..<index].contains { Self.equal($0, element) }
        }
        return unique ? [] : ["\(path): items are not unique"]
      }
    }

    private static func checkString(
      _ keyword: String,
      _ argument: Any,
      _ string: String,
      at path: String
    )
      -> [String]
    {
      switch keyword {
      case "minLength": string.count >= (argument as? Int ?? 0) ? [] : ["\(path): too short"]
      case "maxLength": string.count <= (argument as? Int ?? .max) ? [] : ["\(path): too long"]
      default:
        string.range(of: argument as? String ?? "", options: .regularExpression) != nil
          ? [] : ["\(path): '\(string)' does not match \(argument)"]
      }
    }

    private func resolve(_ reference: String, from file: String) throws -> (Any, String) {
      let parts = reference.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
      let targetFile = parts[0].isEmpty ? file : String(parts[0])
      if documents[targetFile] == nil {
        documents[targetFile] = try CLIOutputSchema.document(named: targetFile)
      }
      var node: Any = documents[targetFile] as Any
      let pointer = parts.count > 1 ? String(parts[1]) : ""
      for token in pointer.split(separator: "/").map(String.init) {
        let key = token.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(
          of: "~0",
          with: "~"
        )
        if let object = node as? [String: Any], let next = object[key] {
          node = next
        } else if let array = node as? [Any], let index = Int(key), array.indices.contains(index) {
          node = array[index]
        } else {
          throw SchemaError("\(file): cannot resolve \(reference)")
        }
      }
      return (node, targetFile)
    }

    /// `JSONSerialization` returns numbers and booleans as `NSNumber`; only the CF type tells
    /// them apart.
    private static func isBoolean(_ value: Any) -> Bool {
      // swiftlint:disable:next legacy_objc_type
      guard let number = value as? NSNumber else { return false }
      return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func number(_ value: Any) -> Double? {
      // swiftlint:disable:next legacy_objc_type
      guard !isBoolean(value), let number = value as? NSNumber else { return nil }
      return number.doubleValue
    }

    private static func matches(_ value: Any, type: String) -> Bool {
      switch type {
      case "null": value is NSNull
      case "boolean": isBoolean(value)
      case "integer": number(value).map { $0.rounded() == $0 } ?? false
      case "number": number(value) != nil
      case "string": value is String
      case "array": value is [Any]
      case "object": value is [String: Any]
      default: false
      }
    }

    private static func equal(_ lhs: Any, _ rhs: Any) -> Bool {
      if isBoolean(lhs) != isBoolean(rhs) { return false }
      return (lhs as? NSObject)?.isEqual(rhs) ?? false
    }
  }
}
