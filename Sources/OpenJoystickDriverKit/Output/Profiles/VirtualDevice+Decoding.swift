import Foundation

extension VirtualDevice {
  /// Where a document came from, which decides whether a header problem names a file.
  enum Source {
    /// A file of this name.
    case file(String)
    /// A document held in memory, such as one the caller reads and names itself.
    case unnamed
  }

  /// Decodes one `virtual-device.schema.json` document. `requiresMatch` refuses a document
  /// without `match`, which would otherwise be read as a persona definition.
  ///
  /// - Throws: ``DocumentHeaderProblem`` carrying E5001 when `apiVersion` or `kind` is not the
  ///   supported one, and ``ControllerRecordProblem`` for any other violation of the schema.
  static func decode(
    _ data: Data,
    source: Source,
    requiresMatch: Bool
  ) throws -> Self {
    guard let object = try? JSONSerialization.jsonObject(with: data),
      let document = object as? [String: Any]
    else {
      throw ControllerRecordProblem(code: .invalidControllerRecord, "the file is not a JSON object")
    }
    if let problem = OpenJoystickDriverAPI.headerProblem(
      apiVersion: document["apiVersion"],
      kind: document["kind"],
      expected: kind
    ) {
      let located: String
      switch source {
      case .file(let name): located = problem.located(in: name).message
      case .unnamed: located = problem.message
      }
      throw DocumentHeaderProblem(code: .unsupportedAPIVersion, located)
    }
    let allowed: Set<String> = [
      "apiVersion", "kind", "persona", "match", "layout", "transport", "labels", "identity",
      "worksWithDefaultSDLHints",
    ]
    guard Set(document.keys).isSubset(of: allowed) else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        "the file must hold only \(allowed.sorted().joined(separator: ", "))"
      )
    }
    guard let persona = (document["persona"] as? String).flatMap(VirtualHIDProfileID.init)
    else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        "persona must be one of "
          + VirtualHIDProfileID.allCases.map(\.rawValue).joined(separator: ", ")
      )
    }
    if requiresMatch, document["match"] == nil {
      throw ControllerRecordProblem(code: .invalidControllerRecord, "the file must hold match")
    }
    let match = try document["match"].map(Self.match)
    let layout = try document["layout"].map { value in
      guard let layout = (value as? String).flatMap(VirtualDeviceLayout.init) else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          "layout must be one of "
            + VirtualDeviceLayout.allCases.map(\.rawValue).joined(separator: ", ")
        )
      }
      return layout
    }
    let transport = try document["transport"].map { value in
      guard let transport = value as? String, ["USB", "Bluetooth"].contains(transport) else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          "transport must be USB or Bluetooth"
        )
      }
      return transport
    }
    let labels = try document["labels"].map { value in
      guard let labels = (value as? String).flatMap(VirtualIdentityGlyphFamily.init) else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          "labels must be Xbox or Generic"
        )
      }
      return labels
    }
    let worksWithDefaultSDLHints = try document["worksWithDefaultSDLHints"].map { value in
      // swiftlint:disable:next legacy_objc_type
      guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          "worksWithDefaultSDLHints must be true or false"
        )
      }
      return number.boolValue
    }
    let identity = try document["identity"].map(Self.identity)
    if match != nil {
      guard layout == nil, transport == nil, worksWithDefaultSDLHints == nil else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          "a file with match selects a persona and holds no layout, transport, or "
            + "worksWithDefaultSDLHints"
        )
      }
    } else {
      guard layout != nil, transport != nil, labels != nil, worksWithDefaultSDLHints != nil,
        let identity, identity.versionNumber != nil
      else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          "a persona definition must hold layout, transport, labels, worksWithDefaultSDLHints, "
            + "and identity with version"
        )
      }
    }
    return Self(
      persona: persona,
      match: match,
      layout: layout,
      transport: transport,
      labels: labels,
      worksWithDefaultSDLHints: worksWithDefaultSDLHints,
      identity: identity
    )
  }

  /// The model, and optionally the unit, that a document's `match` names.
  ///
  /// - Throws: `ControllerRecordProblem` when `match` holds other fields, or a vendor ID, product
  ///   ID or unit that is out of range.
  private static func match(_ value: Any) throws -> VirtualHIDProfileOverrideStore.Model {
    let match = try fields(
      value,
      named: "match",
      required: ["vendorID", "productID"],
      optional: ["unit"]
    )
    let unit = match["unit"] as? String
    if match["unit"] != nil, unit.flatMap(ControllerPortKey.init(rawValue:)) == nil {
      throw ControllerRecordProblem(code: .invalidControllerRecord, "match.unit is not a unit ID")
    }
    return VirtualHIDProfileOverrideStore.Model(
      vendorID: try id(match["vendorID"], "match.vendorID", from: 1),
      productID: try id(match["productID"], "match.productID", from: 0),
      unit: unit
    )
  }

  /// The identity of a document's `identity` object.
  ///
  /// - Throws: `ControllerRecordProblem` when a field is missing, unknown, empty or out of range.
  private static func identity(_ value: Any) throws -> Identity {
    let fields = try fields(
      value,
      named: "identity",
      required: ["vendorID", "productID", "productName", "manufacturer"],
      optional: ["version"]
    )
    func text(_ key: String) throws -> String {
      guard let value = fields[key] as? String, !value.isEmpty else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          "identity.\(key) must be a nonempty string"
        )
      }
      return value
    }
    let version = try fields["version"].map { try id($0, "identity.version", from: 0) }
    return Identity(
      vendorID: try id(fields["vendorID"], "identity.vendorID", from: 1),
      productID: try id(fields["productID"], "identity.productID", from: 0),
      versionNumber: version.map(Int.init),
      productName: try text("productName"),
      manufacturer: try text("manufacturer")
    )
  }

  /// The fields of the object `value` named `name`.
  ///
  /// - Throws: `ControllerRecordProblem` when `value` is not an object, lacks a required field, or
  ///   holds a field that is neither required nor optional.
  private static func fields(
    _ value: Any?,
    named name: String,
    required: Set<String>,
    optional: Set<String>
  ) throws -> [String: Any] {
    guard let object = value as? [String: Any],
      Set(object.keys).isSubset(of: required.union(optional)),
      required.isSubset(of: Set(object.keys))
    else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        "\(name) must hold \(required.union(optional).sorted().joined(separator: ", "))"
      )
    }
    return object
  }

  /// The integer ID in `minimum...65535` that `value` holds.
  ///
  /// - Throws: `ControllerRecordProblem` naming `name` when `value` is not a whole number in that
  ///   range.
  private static func id(_ value: Any?, _ name: String, from minimum: Int) throws -> UInt16 {
    // swiftlint:disable:next legacy_objc_type
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
      let integer = Int(exactly: number.doubleValue), integer >= minimum,
      let id = UInt16(exactly: integer)
    else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        "\(name) must be \(minimum)...65535"
      )
    }
    return id
  }
}
