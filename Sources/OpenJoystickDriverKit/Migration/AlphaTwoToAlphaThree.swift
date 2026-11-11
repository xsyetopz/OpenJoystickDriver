import Foundation

/// `openjoystickdriver/v1alpha2` to `openjoystickdriver/v1alpha3`.
///
/// A property list has no `null`, so a patch `null` becomes a `remove` entry and any other `null`
/// leaves its key out. A patch that sets `modes` also removes `modes`, so it keeps replacing the
/// record's modes. `notes` and `rationale` are not keys of `v1alpha3`.
enum AlphaTwoToAlphaThree {
  /// The version the step reads.
  static let from = "openjoystickdriver/v1alpha2"
  /// The version the step writes.
  static let to = OpenJoystickDriverAPI.version

  /// The keys that `v1alpha3` does not have.
  private static let droppedKeys: Set<String> = ["notes", "rationale"]

  /// Converts `document` of `kind`.
  ///
  /// - Throws: ``DocumentMigrationProblem`` for a `null` that has no place to go.
  static func convert(_ document: OrderedJSON, kind: DocumentKind) throws -> OrderedJSON {
    guard case .object(let members) = document else {
      throw DocumentMigrationProblem("the file is not a JSON object")
    }
    var converted: [OrderedJSON.Member] = []
    var removed: [String] = []
    for member in members {
      switch member.key {
      case "apiVersion": converted.append(.init(key: member.key, value: .string(to)))
      case "patch" where kind == .controllerPatch:
        try collectNulls(member.value, path: [], into: &removed)
        let body = try stripped(member.value, path: "patch")
        if case .object(let sections) = body, sections.isEmpty { continue }
        // `v1alpha2` replaced the whole `modes` list; `v1alpha3` merges it by `id`.
        if body["modes"] != nil { removed.append("modes") }
        converted.append(.init(key: member.key, value: body))
      default:
        guard !droppedKeys.contains(member.key), member.value != .null else { continue }
        converted.append(.init(key: member.key, value: try stripped(member.value, path: member.key)))
      }
    }
    if !removed.isEmpty {
      converted.append(.init(key: "remove", value: .array(removed.map { .string($0) })))
    }
    return .object(converted)
  }

  /// The dotted key path of each `null` in `value`, in document order.
  private static func collectNulls(
    _ value: OrderedJSON,
    path: [String],
    into removed: inout [String]
  ) throws {
    guard case .object(let members) = value else { return }
    for member in members {
      let next = path + [member.key]
      if member.value == .null {
        guard next.allSatisfy({ $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) } }) else {
          throw DocumentMigrationProblem("\(next.joined(separator: ".")) has no remove path")
        }
        removed.append(next.joined(separator: "."))
      } else {
        try collectNulls(member.value, path: next, into: &removed)
      }
    }
  }

  /// `value` without `null` members and without the dropped keys.
  private static func stripped(_ value: OrderedJSON, path: String) throws -> OrderedJSON {
    switch value {
    case .object(let members):
      var kept: [OrderedJSON.Member] = []
      for member in members where !droppedKeys.contains(member.key) && member.value != .null {
        let value = try stripped(member.value, path: "\(path).\(member.key)")
        // A section whose members were all `null` has nothing left to say.
        if value == .object([]), member.value != .object([]) { continue }
        kept.append(.init(key: member.key, value: value))
      }
      return .object(kept)
    case .array(let items):
      return .array(
        try items.enumerated().map { offset, item in
          guard item != .null else {
            throw DocumentMigrationProblem("\(path)[\(offset)] is null, which a list cannot hold")
          }
          return try stripped(item, path: "\(path)[\(offset)]")
        }
      )
    default: return value
    }
  }
}
