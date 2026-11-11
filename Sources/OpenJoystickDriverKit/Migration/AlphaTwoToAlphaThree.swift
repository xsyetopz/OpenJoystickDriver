import Foundation

/// `openjoystickdriver/v1alpha2` to `openjoystickdriver/v1alpha3`.
///
/// A property list has no `null`, so a patch `null` becomes a `remove` entry and any other `null`
/// leaves its key out. A patch that sets `modes` also removes `modes`, so it keeps replacing the
/// record's modes. `notes` and `rationale` are not keys of `v1alpha3`. The `appID` of a
/// profile's application scope becomes `appIDs`, a list of one.
/// A record's `idle`, and a patch's, becomes `"idle": "NoControllerLinked"` on the `default` mode.
enum AlphaTwoToAlphaThree {
  /// The version the step reads.
  static let from = "openjoystickdriver/v1alpha2"
  /// The version the step writes.
  static let to = OpenJoystickDriverAPI.version

  /// The keys that `v1alpha3` does not have.
  private static let droppedKeys: Set<String> = ["notes", "rationale"]

  /// `scope`, an `applicationScope`, with its `appID` as an `appIDs` list of one.
  ///
  /// - Throws: ``DocumentMigrationProblem`` for an `appID` that is not a string.
  static func listedApps(_ scope: OrderedJSON) throws -> OrderedJSON {
    guard case .object(let members) = scope else { return scope }
    return .object(
      try members.map { member in
        guard member.key == "appID" else { return member }
        guard case .string = member.value else {
          throw DocumentMigrationProblem("applicationScope.appID is not a string")
        }
        return .init(key: "appIDs", value: .array([member.value]))
      }
    )
  }

  /// `entries`, the root array of `ActiveProfiles`, with each `applicationScope` converted.
  static func activeProfiles(_ entries: OrderedJSON) throws -> OrderedJSON {
    guard case .array(let items) = entries else { return entries }
    return .array(
      try items.map { item in
        guard case .object(let members) = item else { return item }
        return .object(
          try members.map {
            $0.key == "applicationScope" ? .init(key: $0.key, value: try listedApps($0.value)) : $0
          }
        )
      }
    )
  }

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
      case "applicationScope" where kind == .profile:
        converted.append(.init(key: member.key, value: try listedApps(member.value)))
      case "idle" where kind == .controller: continue
      case "modes" where kind == .controller && document["idle"] == .bool(true):
        converted.append(.init(key: member.key, value: idledDefault(member.value)))
      case "patch" where kind == .controllerPatch:
        guard member.value["idle"] != .null else {
          throw DocumentMigrationProblem("patch.idle is null, which no mode can state")
        }
        try collectNulls(member.value, path: [], into: &removed)
        var body = try stripped(member.value, path: "patch")
        // `v1alpha2` replaced the whole `modes` list; `v1alpha3` merges it by `id`.
        if body["modes"] != nil { removed.append("modes") }
        body = movedIdle(body)
        if case .object(let sections) = body, sections.isEmpty { continue }
        converted.append(.init(key: member.key, value: body))
      default:
        guard !droppedKeys.contains(member.key), member.value != .null else { continue }
        converted.append(
          .init(key: member.key, value: try stripped(member.value, path: member.key))
        )
      }
    }
    if !removed.isEmpty {
      converted.append(.init(key: "remove", value: .array(removed.map { .string($0) })))
    }
    return .object(converted)
  }

  /// `modes` with the reason `NoControllerLinked` on its `default` mode, which is where a record's
  /// `idle` goes.
  private static func idledDefault(_ modes: OrderedJSON) -> OrderedJSON {
    guard case .array(let items) = modes else { return modes }
    return .array(
      items.map { item in
        guard case .object(let members) = item, item["id"]?.string == "default" else { return item }
        return .object(members + [.init(key: "idle", value: .string("NoControllerLinked"))])
      }
    )
  }

  /// `patch` with its `idle` moved to the `default` entry of its `modes`, which a patch merges by
  /// `id`; an `idle` of `false` says nothing and is dropped.
  private static func movedIdle(_ patch: OrderedJSON) -> OrderedJSON {
    guard case .object(let members) = patch, let idle = patch["idle"] else { return patch }
    var kept = members.filter { $0.key != "idle" }
    guard idle == .bool(true) else { return .object(kept) }
    let entry = OrderedJSON.object([
      .init(key: "id", value: .string("default")),
      .init(key: "idle", value: .string("NoControllerLinked")),
    ])
    guard let index = kept.firstIndex(where: { $0.key == "modes" }) else {
      kept.append(.init(key: "modes", value: .array([entry])))
      return .object(kept)
    }
    let modes = kept[index].value
    let hasDefault = modes.array?.contains { $0["id"]?.string == "default" } == true
    kept[index] = .init(
      key: "modes",
      value: hasDefault ? idledDefault(modes) : .array((modes.array ?? []) + [entry])
    )
    return .object(kept)
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
        guard next.allSatisfy({ $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) } })
        else {
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
        let cleaned = try stripped(member.value, path: "\(path).\(member.key)")
        // A section whose members were all `null` has nothing left to say.
        if cleaned == .object([]), member.value != .object([]) { continue }
        kept.append(.init(key: member.key, value: cleaned))
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
