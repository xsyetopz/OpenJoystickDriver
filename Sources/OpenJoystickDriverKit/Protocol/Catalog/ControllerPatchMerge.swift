import Foundation

/// The RFC 7396 merge that layers controller patches over a record.
enum ControllerPatchMerge {
  // RFC 7396 `MergePatch` over ``OrderedJSON`` without the deleting `null`: an array or scalar
  // replaces. A patch deletes keys through `remove`, see ``removing(_:from:)``.
  // An object patch over a value that is not an object starts from an empty object.
  // Where both are objects the members stay in the target's order and the members the target
  // lacks come after, in the patch's order, at every depth. A value the patch replaces has the
  // patch's order. A number keeps its text.
  static func mergePatch(_ target: OrderedJSON?, _ patch: OrderedJSON) -> OrderedJSON {
    guard case .object(let patchMembers) = patch else { return patch }
    var members = target?.members ?? []
    for member in patchMembers {
      let index = members.firstIndex { $0.key == member.key }
      let merged = OrderedJSON.Member(
        key: member.key,
        value: mergePatch(index.map { members[$0].value }, member.value)
      )
      if let index { members[index] = merged } else { members.append(merged) }
    }
    return .object(members)
  }

  /// RFC 7396 `MergePatch` of a patch body over a record: the `modes` entries merge by `id`, see
  /// ``mergeModes(_:_:)``, and every other member merges as ``mergePatch(_:_:)`` does.
  static func mergeRecordPatch(_ record: OrderedJSON, _ body: OrderedJSON) -> OrderedJSON {
    guard case .object(let members) = body else { return body }
    return members.reduce(record) { record, member in
      let value =
        member.key == "modes" ? mergeModes(record["modes"], member.value) : member.value
      return mergePatch(record, .object([.init(key: member.key, value: value)]))
    }
  }

  // An entry whose `id` the target holds merges key by key into that mode, and an entry with
  // another `id` is added last. A patch over a target that is not a list replaces it.
  static func mergeModes(_ target: OrderedJSON?, _ patch: OrderedJSON) -> OrderedJSON {
    guard case .array(let entries) = patch, case .array(var modes)? = target else { return patch }
    for entry in entries {
      if let index = modes.firstIndex(where: { $0["id"] == entry["id"] }) {
        modes[index] = mergePatch(modes[index], entry)
      } else {
        modes.append(entry)
      }
    }
    return .array(modes)
  }

  /// `value` without the key that `path` names; `value` itself when it does not hold the path.
  ///
  /// The path is a list of keys from the top of `value`. A key that leads through a value that is
  /// not an object holds nothing. The path `modes.<id>` names the mode of that `id`.
  static func removing(_ path: [String], from value: OrderedJSON) -> OrderedJSON {
    guard let key = path.first, var members = value.members,
      let index = members.firstIndex(where: { $0.key == key })
    else { return value }
    if path.count == 1 {
      members.remove(at: index)
    } else if key == "modes", path.count == 2, case .array(let modes) = members[index].value {
      members[index] = .init(
        key: key,
        value: .array(modes.filter { $0["id"]?.string != path[1] })
      )
    } else {
      members[index] = .init(
        key: key,
        value: removing(Array(path.dropFirst()), from: members[index].value)
      )
    }
    return .object(members)
  }

  /// `items` ordered for one layer, least specific first: by selector rank, then file name, then
  /// owning package name (a user file has none), then position, so the order is total and the
  /// same on every run.
  static func ordered<Item>(
    _ items: [Item],
    by key: (Item) -> (patch: ControllerPatch, owner: String?)
  ) -> [Item] {
    items.enumerated().map { (offset: $0.offset, item: $0.element, key: key($0.element)) }
      .sorted {
        (
          $0.key.patch.selector.rank, $0.key.patch.selector.fileName, $0.key.owner ?? "",
          $0.offset
        )
          < (
            $1.key.patch.selector.rank, $1.key.patch.selector.fileName, $1.key.owner ?? "",
            $1.offset
          )
      }
      .map(\.item)
  }

  /// `patches` ordered for one layer, with no owners.
  static func ordered(_ patches: [ControllerPatch]) -> [ControllerPatch] {
    ordered(patches) { ($0, nil) }
  }

  /// The merge patch that `patch` gives to the record `document`, or nil when it changes nothing to
  /// apply.
  ///
  /// A patch with a selector other than `all` gives its whole body. An `all` patch gives only the
  /// `tuning` keys that the record's family reads; a `tuning` that is not an object gives nothing.
  static func appliedBody(of patch: ControllerPatch, to document: OrderedJSON) -> OrderedJSON? {
    guard patch.selector == .all else {
      return patch.body.members?.isEmpty == false ? patch.body : nil
    }
    let scope = Set(ControllerTuning.scope(ofDocument: document).map(\.rawValue))
    let tuning = (patch.body["tuning"]?.members ?? []).filter { scope.contains($0.key) }
    return tuning.isEmpty ? nil : .object([.init(key: "tuning", value: .object(tuning))])
  }

  /// The key paths that `patch` removes from the record `document`.
  ///
  /// A patch with a selector other than `all` removes every path it lists. An `all` patch removes
  /// only the `tuning` keys that the record's family reads.
  static func appliedRemove(of patch: ControllerPatch, to document: OrderedJSON) -> [[String]] {
    guard patch.selector == .all else { return patch.remove }
    let scope = Set(ControllerTuning.scope(ofDocument: document).map(\.rawValue))
    return patch.remove.filter { scope.contains($0[1]) }
  }

  /// `document` with the removals of `patch` applied and then its merge patch; `document` itself
  /// when the patch gives nothing.
  static func apply(_ patch: ControllerPatch, to document: OrderedJSON) -> OrderedJSON {
    var result = document
    for path in appliedRemove(of: patch, to: document) { result = removing(path, from: result) }
    guard let body = appliedBody(of: patch, to: document) else { return result }
    return mergeRecordPatch(result, body)
  }

  /// `record` with the built-in, package, and user patches applied in that order.
  ///
  /// A package layer entry may name its owner. A record with no valid `vendorID` and `productID` is
  /// returned unchanged.
  static func effective(
    record: OrderedJSON,
    builtin: [ControllerPatch],
    package: [(patch: ControllerPatch, owner: String?)],
    user: [ControllerPatch]
  ) -> OrderedJSON {
    guard let vendorID = record["vendorID"]?.integer.flatMap(UInt16.init(exactly:)),
      let productID = record["productID"]?.integer.flatMap(UInt16.init(exactly:))
    else { return record }
    let model = ControllerModelID(vendorID: vendorID, productID: productID)
    let layers: [[(patch: ControllerPatch, owner: String?)]] = [
      builtin.map { ($0, nil) }, package, user.map { ($0, nil) },
    ]
    var result = record
    for layer in layers {
      for entry in ordered(layer.filter { $0.patch.selector.selects(model) }, by: { $0 }) {
        result = apply(entry.patch, to: result)
      }
    }
    return result
  }
}
