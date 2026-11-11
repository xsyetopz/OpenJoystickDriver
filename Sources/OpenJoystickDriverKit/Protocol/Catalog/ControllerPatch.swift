import Foundation

/// A `ControllerPatch` document from `controller-patch.schema.json`: an RFC 7396 merge patch and
/// the selector of the records it applies to.
///
/// The layers apply in the order catalog record, built-in patch, package patch, user patch. Inside
/// one layer the selectors apply in the order `all`, `vendorID` with `productID`, `model`, so the
/// more specific selector wins. A `null` deletes a key and an array replaces the array. The
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
        String(format: "%04x-%04x.patch.plist", model.vendorID, model.productID)
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
  /// The top-level record sections a patch may set.
  static let sections: Set<String> = [
    "modes", "usb", "bluetoothLE", "server", "route", "input",
    "tuning",
  ]

  /// The records the patch applies to.
  public let selector: Selector
  /// The merge patch, an object, with the member order and the number text of the patch file.
  let body: OrderedJSON

  /// The model id of `model`: `vvvv-pppp` in lowercase hex.
  public static func modelID(of model: ControllerModelID) -> String {
    String(format: "%04x-%04x", model.vendorID, model.productID)
  }

  /// The document of a patch with `selector` and `body`.
  static func document(selector: Selector, body: [String: Any]) -> [String: Any] {
    let selected: [String: Any]
    switch selector {
    case .all: selected = ["all": true]
    case .identity(let model):
      selected = ["vendorID": Int(model.vendorID), "productID": Int(model.productID)]
    case .model(let id): selected = ["model": id]
    }
    return [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": kind, "selector": selected,
      "patch": body,
    ]
  }

  /// Checks and reads a patch document.
  ///
  /// A document of another kind fails the header check.
  static func parse(_ document: OrderedJSON, file: String? = nil) throws -> Self {
    guard let members = document.members else {
      throw ControllerRecordProblem(code: .invalidControllerRecord, "the file is not a JSON object")
    }
    try OpenJoystickDriverAPI.requireHeader(
      apiVersion: document["apiVersion"],
      kind: document["kind"],
      expected: kind,
      file: file
    )
    guard Set(members.map(\.key)) == ["apiVersion", "kind", "selector", "patch"],
      let selector = document["selector"], case .object(let body)? = document["patch"]
    else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        "the file must hold exactly apiVersion, kind, selector, and patch"
      )
    }
    let parsed = try parseSelector(selector)
    guard !body.isEmpty, Set(body.map(\.key)).isSubset(of: sections) else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        "patch must hold modes, usb, bluetoothLE, server, "
          + "route, input, or tuning"
      )
    }
    if parsed == .all, Set(body.map(\.key)) != ["tuning"] {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        "an all patch may set only tuning"
      )
    }
    return Self(selector: parsed, body: .object(body))
  }

  /// Reads a patch selector: `all`, a vendor ID with a product ID, or a model ID; any other shape
  /// is rejected.
  private static func parseSelector(_ selector: OrderedJSON) throws -> Selector {
    guard let members = selector.members else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        "selector must be all, model, or vendorID with productID"
      )
    }
    switch Set(members.map(\.key)) {
    case ["all"]:
      guard selector["all"] == .bool(true) else {
        throw ControllerRecordProblem(code: .invalidControllerRecord, "selector.all must be true")
      }
      return .all
    case ["vendorID", "productID"]:
      guard let vendorID = selector["vendorID"]?.integer.flatMap(UInt16.init(exactly:)),
        vendorID >= 1,
        let productID = selector["productID"]?.integer.flatMap(UInt16.init(exactly:))
      else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          "vendorID must be 1...65535 and productID 0...65535"
        )
      }
      return .identity(ControllerModelID(vendorID: vendorID, productID: productID))
    case ["model"]:
      guard let id = selector["model"]?.string, isModelID(id) else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          "selector.model must be vvvv-pppp in lowercase hex"
        )
      }
      return .model(id)
    default:
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        "selector must be all, model, or vendorID with productID"
      )
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
  /// RFC 7396 `MergePatch` over ``OrderedJSON``: `null` deletes, an array or scalar replaces.
  ///
  /// An object patch over a value that is not an object starts from an empty object.
  ///
  /// Where both are objects the members stay in the target's order and the members the target
  /// lacks come after, in the patch's order, at every depth. A value the patch replaces has the
  /// patch's order. A number keeps its text.
  static func mergePatch(_ target: OrderedJSON?, _ patch: OrderedJSON) -> OrderedJSON {
    guard case .object(let patchMembers) = patch else { return patch }
    var members = target?.members ?? []
    for member in patchMembers {
      let index = members.firstIndex { $0.key == member.key }
      if case .null = member.value {
        if let index { members.remove(at: index) }
        continue
      }
      let merged = OrderedJSON.Member(
        key: member.key,
        value: mergePatch(index.map { members[$0].value }, member.value)
      )
      if let index { members[index] = merged } else { members.append(merged) }
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
    guard patch.selector == .all else { return patch.body }
    let scope = Set(ControllerTuning.scope(ofDocument: document).map(\.rawValue))
    let tuning = (patch.body["tuning"]?.members ?? []).filter { scope.contains($0.key) }
    return tuning.isEmpty ? nil : .object([.init(key: "tuning", value: .object(tuning))])
  }

  /// `document` with `patch` merged in; `document` itself when the patch gives nothing.
  static func apply(_ patch: ControllerPatch, to document: OrderedJSON) -> OrderedJSON {
    guard let body = appliedBody(of: patch, to: document) else { return document }
    return mergePatch(document, body)
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
