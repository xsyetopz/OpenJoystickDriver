import Foundation

/// A `ControllerPatch` document from `controller-patch.schema.json`: a merge patch, the dotted key
/// paths it removes, and the selector of the records it applies to.
///
/// The layers apply in the order catalog record, built-in patch, package patch, user patch. Inside
/// one layer the selectors apply in the order `all`, `vendorID` with `productID`, `model`, so the
/// more specific selector wins. A patch applies its `remove` paths first and its `patch` second,
/// and an array in `patch` replaces the array, except `modes`, whose entries merge by `id`. The
/// patch body and the record it changes are ``OrderedJSON``, so a merged record keeps its file's
/// member order and the text of its numbers.
public struct ControllerPatch: Equatable, Sendable {
  /// Which records a patch applies to.
  public enum Selector: Equatable, Sendable, CustomStringConvertible {
    /// Every record. Such a patch may set only `tuning`.
    case all
    /// The record with this vendor ID and product ID.
    case identity(ControllerModelID)
    /// The record with this model id, `vvvv-pppp` in lowercase hex until records carry their own.
    case model(String)

    /// 0 for `all`, 1 for `vendorID` with `productID`, 2 for `model`: a higher rank applies later.
    public var rank: Int {
      switch self {
      case .all: 0
      case .identity: 1
      case .model: 2
      }
    }

    /// A short name of the selector for messages.
    public var description: String {
      switch self {
      case .all: "all controllers"
      case .identity(let model): model.description
      case .model(let id): id
      }
    }

    /// The file name of a patch with this selector in a `Controllers` folder.
    public var fileName: String {
      switch self {
      case .all: "all.patch.plist"
      case .identity(let model):
        unsafe String(format: "%04x-%04x.patch.plist", model.vendorID, model.productID)
      case .model(let id): "model-\(id).patch.plist"
      }
    }

    /// Whether a patch with this selector applies to `model`.
    public func selects(_ model: ControllerModelID) -> Bool {
      switch self {
      case .all: true
      case .identity(let identity): identity == model
      case .model(let id): id == ControllerPatch.modelID(of: model)
      }
    }
  }

  /// The `kind` of a patch document.
  public static let kind = "ControllerPatch"
  /// The top-level record properties a patch may set: every property but the identity
  /// (`apiVersion`, `kind`, `vendorID`, `productID`), which the selector names.
  static let sections: Set<String> = [
    "modes", "name", "placeholderSerial", "usb", "bluetoothLE", "capabilities", "server",
    "route", "heldByAppleDriver", "input", "tuning",
  ]

  /// The records the patch applies to.
  public let selector: Selector
  // The member order and the number text of the patch file. It is empty for a patch that only
  // removes keys.
  let body: OrderedJSON
  /// The key paths the patch removes, each a list of keys from the record's top level down.
  let remove: [[String]]

  /// A patch with `selector`, the merge patch `body`, and the key paths `remove`.
  init(selector: Selector, body: OrderedJSON, remove: [[String]] = []) {
    self.selector = selector
    self.body = body
    self.remove = remove
  }

  /// The model id of `model`: `vvvv-pppp` in lowercase hex.
  public static func modelID(of model: ControllerModelID) -> String {
    unsafe String(format: "%04x-%04x", model.vendorID, model.productID)
  }

  /// The document of a patch with `selector` and `body`.
  static func document(
    selector: Selector,
    body: [String: Any],
    remove: [String] = []
  ) -> [String: Any] {
    let selected: [String: Any]
    switch selector {
    case .all: selected = ["all": true]
    case .identity(let model):
      selected = ["vendorID": Int(model.vendorID), "productID": Int(model.productID)]
    case .model(let id): selected = ["model": id]
    }
    var document: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": kind, "selector": selected,
    ]
    if !body.isEmpty { document["patch"] = body }
    if !remove.isEmpty { document["remove"] = remove }
    return document
  }

  /// Checks and reads a patch document.
  ///
  /// A document of another kind fails the header check.
  static func parse(_ document: OrderedJSON, file: String? = nil) throws -> Self {
    guard let members = document.members else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.patch.patchNotObject",
        "the file is not a JSON object"
      )
    }
    try OpenJoystickDriverAPI.requireHeader(
      apiVersion: document["apiVersion"],
      kind: document["kind"],
      expected: kind,
      file: file
    )
    let keys = Set(members.map(\.key))
    guard keys.isSuperset(of: ["apiVersion", "kind", "selector"]),
      keys.isSubset(of: ["apiVersion", "kind", "selector", "patch", "remove"]),
      keys.contains("patch") || keys.contains("remove"),
      let selectorValue = document["selector"]
    else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.patch.patchFields",
        "the file must hold apiVersion, kind, selector, and patch or remove"
      )
    }
    let parsed = try parseSelector(selectorValue)
    var patchMembers: [OrderedJSON.Member] = []
    if let patch = document["patch"] {
      guard case .object(let members) = patch, !members.isEmpty,
        Set(members.map(\.key)).isSubset(of: sections)
      else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          key: "error.E5007.patch.patchSections",
          "patch must hold modes, name, placeholderSerial, usb, bluetoothLE, capabilities, "
            + "server, route, heldByAppleDriver, input, or tuning; the selector names the identity"
        )
      }
      if case .array(let modes)? = patch["modes"],
        !modes.allSatisfy({ isPatchMode($0) })
      {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          key: "error.E5007.patch.patchModeEntries",
          "patch.modes entries must hold an id and only id, protocol, match, interface, session,"
            + " or idle"
        )
      }
      patchMembers = members
    }
    if parsed == .all, !patchMembers.isEmpty, Set(patchMembers.map(\.key)) != ["tuning"] {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.patch.patchAllOnlyTuning",
        "an all patch may set only tuning"
      )
    }
    let removed = try document["remove"].map { try parseRemove($0, selector: parsed) } ?? []
    return Self(selector: parsed, body: .object(patchMembers), remove: removed)
  }

  /// Reads `remove`: a nonempty list of distinct dotted key paths that name a property of the
  /// record schema.
  ///
  /// A path names a top-level property, below `tuning` a tuning key, and `modes.<id>` one mode. An
  /// `all` patch removes only `tuning.<key>`. A path the record does not hold removes nothing.
  private static func parseRemove(
    _ value: OrderedJSON,
    selector: Selector
  ) throws -> [[String]] {
    guard case .array(let items) = value, !items.isEmpty else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.patch.removeNotList",
        "remove must be a nonempty list of dotted key paths"
      )
    }
    var paths: [[String]] = []
    for item in items {
      guard let text = item.string else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          key: "error.E5007.patch.removeNotText",
          "remove must hold dotted key paths as text"
        )
      }
      let path = text.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
      guard !path.contains(where: \.isEmpty), sections.contains(path[0]),
        path[0] != "tuning" || path.count == 1 || ControllerTuning.Key(rawValue: path[1]) != nil,
        path[0] != "modes" || path.count == 1 || (path.count == 2 && isModeID(path[1]))
      else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          key: "error.E5007.patch.removePathUnknown",
          arguments: [text],
          "remove path \(text) is not in the record schema"
        )
      }
      guard !paths.contains(path) else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          key: "error.E5007.patch.removeDuplicate",
          arguments: [text],
          "remove path \(text) is listed twice"
        )
      }
      if selector == .all, path.count != 2 || path[0] != "tuning" {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          key: "error.E5007.patch.removeAllNotTuning",
          arguments: [text],
          "an all patch may remove only tuning keys, not \(text)"
        )
      }
      paths.append(path)
    }
    return paths
  }

  /// Reads a patch selector: `all`, a vendor ID with a product ID, or a model ID; any other shape
  /// is rejected.
  private static func parseSelector(_ selector: OrderedJSON) throws -> Selector {
    guard let members = selector.members else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.patch.selectorNotObject",
        "selector must be all, model, or vendorID with productID"
      )
    }
    switch Set(members.map(\.key)) {
    case ["all"]:
      guard selector["all"] == .bool(true) else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          key: "error.E5007.patch.selectorAllTrue",
          "selector.all must be true"
        )
      }
      return .all
    case ["vendorID", "productID"]:
      guard let vendorID = selector["vendorID"]?.integer.flatMap(UInt16.init(exactly:)),
        vendorID >= 1,
        let productID = selector["productID"]?.integer.flatMap(UInt16.init(exactly:))
      else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          key: "error.E5007.patch.selectorIdRange",
          "vendorID must be 1...65535 and productID 0...65535"
        )
      }
      return .identity(ControllerModelID(vendorID: vendorID, productID: productID))
    case ["model"]:
      guard let id = selector["model"]?.string, isModelID(id) else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          key: "error.E5007.patch.selectorModel",
          "selector.model must be vvvv-pppp in lowercase hex"
        )
      }
      return .model(id)
    default:
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.patch.selectorShape",
        "selector must be all, model, or vendorID with productID"
      )
    }
  }

  /// Whether `mode` is an entry of `patch.modes`: an object with a valid `id`, and only the keys a
  /// mode holds.
  private static func isPatchMode(_ mode: OrderedJSON) -> Bool {
    guard let members = mode.members, let id = mode["id"]?.string else { return false }
    return isModeID(id)
      && Set(members.map(\.key)).isSubset(of: [
        "id", "protocol", "match", "interface", "session", "idle",
      ])
  }

  /// Whether `text` is a mode id: lowercase words of letters and digits joined by `-`, the first
  /// word starting with a letter.
  private static func isModeID(_ text: String) -> Bool {
    let words = text.split(separator: "-", omittingEmptySubsequences: false)
    return words.first?.first?.isLetter == true && !text.hasSuffix("-")
      && words.allSatisfy { word in
        !word.isEmpty && word.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber) }
      }
  }

  /// Whether `text` is `vvvv-pppp` in lowercase hex.
  private static func isModelID(_ text: String) -> Bool {
    let characters = Array(text)
    return characters.count == 9 && characters[4] == "-"
      && characters.enumerated().allSatisfy { offset, character in
        offset == 4 || ("0"..."9" ~= character || "a"..."f" ~= character)
      }
  }
}

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
