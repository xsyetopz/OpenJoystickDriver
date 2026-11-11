import Foundation

/// A document that a migration step cannot convert mechanically.
public struct DocumentMigrationProblem: Error, Equatable, CustomStringConvertible, Sendable {
  /// What has no mechanical mapping, naming the field.
  public let description: String

  /// Creates the problem from its text.
  init(_ description: String) { self.description = description }
}

/// The conversion of one document kind from one older `apiVersion` to the next.
///
/// A step is a pure transform on the document's JSON: it reads no file and holds no state. The
/// readers stay single-version; only ``DocumentMigrator`` applies steps, when the user asks.
struct DocumentMigrationStep: Sendable {
  /// The `kind` of the documents the step converts.
  let kind: String
  /// The `apiVersion` the step reads.
  let from: String
  /// The `apiVersion` the step writes.
  let to: String
  /// Converts the whole document, including its `apiVersion`.
  let convert: @Sendable (OrderedJSON) throws -> OrderedJSON

  /// The steps for every kind, in the order a chain applies them.
  static let all: [Self] = DocumentKind.allCases.flatMap { kind in
    [
      Self(
        kind: kind.rawValue,
        from: AlphaOneToAlphaTwo.from,
        to: AlphaOneToAlphaTwo.to
      ) { try AlphaOneToAlphaTwo.convert($0, kind: kind) },
      Self(
        kind: kind.rawValue,
        from: AlphaTwoToAlphaThree.from,
        to: AlphaTwoToAlphaThree.to
      ) { try AlphaTwoToAlphaThree.convert($0, kind: kind) },
    ]
  }
}

/// The kinds of stored document that a step converts.
enum DocumentKind: String, CaseIterable, Sendable {
  /// `Settings.json`.
  case settings = "Settings"
  /// `AccessGrants.json`.
  case accessGrants = "AccessGrants"
  /// A profile in `Profiles/`.
  case profile = "Profile"
  /// A user controller record in `Controllers/`.
  case controller = "Controller"
  /// A user controller patch in `Controllers/`.
  case controllerPatch = "ControllerPatch"
  /// The `mod` file of a package.
  case modPackage = "ModPackage"
  /// A virtual device file in `VirtualDevices/`.
  case virtualDevice = "VirtualDevice"
}

/// `openjoystickdriver/v1alpha1` to `openjoystickdriver/v1alpha2`.
enum AlphaOneToAlphaTwo {
  /// The version the step reads.
  static let from = "openjoystickdriver/v1alpha1"
  /// The version the step writes.
  static let to = "openjoystickdriver/v1alpha2"

  /// Converts `document` of `kind`.
  ///
  /// - Throws: ``DocumentMigrationProblem`` for a field that has no mechanical mapping.
  static func convert(_ document: OrderedJSON, kind: DocumentKind) throws -> OrderedJSON {
    guard case .object(var members) = document else {
      throw DocumentMigrationProblem("the file is not a JSON object")
    }
    members = members.map {
      $0.key == "apiVersion" ? .init(key: $0.key, value: .string(to)) : $0
    }
    switch kind {
    case .settings, .accessGrants, .virtualDevice, .modPackage: break
    case .profile: members = try members.map { try multiTap($0) }
    case .controller:
      members = try members.map { $0.key == "input" ? try inputMember($0) : $0 }
    case .controllerPatch:
      members = try members.map { member in
        guard member.key == "patch", case .object(let sections) = member.value else {
          return member
        }
        let converted = try sections.map { $0.key == "input" ? try inputMember($0) : $0 }
        return .init(key: member.key, value: .object(converted))
      }
    }
    return .object(members)
  }

  // MARK: Profile

  /// `doubleTap` of a binding becomes a `multiTap` list of one entry with `count` 2.
  private static func multiTap(_ member: OrderedJSON.Member) throws -> OrderedJSON.Member {
    switch member.value {
    case .object(let children):
      let converted = try children.map { try multiTap($0) }
      guard let index = converted.firstIndex(where: { $0.key == "doubleTap" }) else {
        return .init(key: member.key, value: .object(converted))
      }
      guard case .object(let tap) = converted[index].value,
        Set(tap.map(\.key)) == ["destination", "windowMs"],
        !converted.contains(where: { $0.key == "multiTap" })
      else { throw DocumentMigrationProblem("\(member.key).doubleTap has no multiTap form") }
      var result = converted
      let entry = OrderedJSON.object([.init(key: "count", value: .number("2"))] + tap)
      result[index] = .init(key: "multiTap", value: .array([entry]))
      return .init(key: member.key, value: .object(result))
    case .array(let items):
      let converted = try items.map { item in
        try multiTap(.init(key: member.key, value: item)).value
      }
      return .init(key: member.key, value: .array(converted))
    default: return member
    }
  }

  // MARK: Controller input

  /// `input` with `report`, `buttons`, `axes`, `hat` and triggers becomes `{ "layouts": [...] }`
  /// with bit-addressed fields; a `hidUsageMap` input and a `null` stay.
  private static func inputMember(_ member: OrderedJSON.Member) throws -> OrderedJSON.Member {
    guard case .object(let fields) = member.value else {
      guard member.value == .null else { throw noMapping("input", "is not an object") }
      return member
    }
    if fields.map(\.key) == ["hidUsageMap"] { return member }
    guard fields.contains(where: { $0.key == "report" }) else {
      throw noMapping("input", "has no report, so its layout cannot be named")
    }
    let layout = try fields.map { field -> OrderedJSON.Member in
      switch field.key {
      case "report": return field
      case "buttons": return try list(field, button)
      case "axes": return try list(field, axis)
      case "hat": return try list(field, hat)
      case "leftTrigger", "rightTrigger":
        return try .init(
          key: field.key,
          value: trigger(field)
        )
      default: throw noMapping("input.\(field.key)", "is not a field of an input layout")
      }
    }
    let wrapped = OrderedJSON.object([
      .init(key: "layouts", value: .array([.object(layout)]))
    ])
    return .init(key: member.key, value: wrapped)
  }

  /// The error of a field that has no new form.
  private static func noMapping(_ field: String, _ reason: String) -> DocumentMigrationProblem {
    DocumentMigrationProblem("\(field) \(reason)")
  }

  /// `field` with each item of its array converted by `convert`.
  private static func list(
    _ field: OrderedJSON.Member,
    _ convert: (String, [OrderedJSON.Member]) throws -> [OrderedJSON.Member]
  ) throws -> OrderedJSON.Member {
    guard case .array(let items) = field.value else {
      throw noMapping("input.\(field.key)", "is not an array")
    }
    let converted = try items.enumerated().map { offset, item -> OrderedJSON in
      guard case .object(let members) = item else {
        throw noMapping("input.\(field.key)[\(offset)]", "is not an object")
      }
      return .object(try convert("input.\(field.key)[\(offset)]", members))
    }
    return .init(key: field.key, value: .array(converted))
  }

  /// The integer of the member `key`, or nil.
  private static func integer(_ members: [OrderedJSON.Member], _ key: String) -> Int? {
    guard case .number(let text)? = members.first(where: { $0.key == key })?.value else {
      return nil
    }
    return Int(text)
  }

  /// `members` with `byte` and `mask` as `bitOffset` and `bitSize` at the place of `byte`.
  private static func masked(
    _ path: String,
    _ members: [OrderedJSON.Member]
  ) throws -> [OrderedJSON.Member] {
    guard let byte = integer(members, "byte"), let mask = integer(members, "mask"), mask > 0,
      case let shifted = mask >> mask.trailingZeroBitCount, shifted & (shifted + 1) == 0
    else { throw noMapping(path, "has a byte and a mask that are not one run of bits") }
    return addressed(
      members,
      bitOffset: byte * 8 + mask.trailingZeroBitCount,
      bitSize: shifted.nonzeroBitCount
    )
  }

  /// `members` without `byte`, `mask` and `bits`, with `bitOffset` and `bitSize` at the place of
  /// `byte`.
  private static func addressed(
    _ members: [OrderedJSON.Member],
    bitOffset: Int,
    bitSize: Int
  ) -> [OrderedJSON.Member] {
    members.flatMap { member -> [OrderedJSON.Member] in
      switch member.key {
      case "byte":
        [
          .init(key: "bitOffset", value: .number(String(bitOffset))),
          .init(key: "bitSize", value: .number(String(bitSize))),
        ]
      case "mask", "bits": []
      default: [member]
      }
    }
  }

  /// `inputField`: `byte` and `mask`.
  private static func field(_ member: OrderedJSON.Member) throws -> OrderedJSON.Member {
    guard case .object(let members) = member.value else {
      throw noMapping("input.\(member.key)", "is not an object")
    }
    return .init(
      key: member.key,
      value: .object(try masked("input.\(member.key)", members))
    )
  }

  /// `inputButton`.
  private static func button(
    _ path: String,
    _ members: [OrderedJSON.Member]
  ) throws -> [OrderedJSON.Member] {
    try masked(path, members)
  }

  /// `inputAxis`: `byte` and `bits` of 8 or 16, which a 16-bit axis reads little-endian.
  private static func axis(
    _ path: String,
    _ members: [OrderedJSON.Member]
  ) throws -> [OrderedJSON.Member] {
    let bits = integer(members, "bits") ?? 8
    guard let byte = integer(members, "byte"), bits == 8 || bits == 16 else {
      throw noMapping(path, "has no byte, or bits other than 8 and 16")
    }
    return addressed(members, bitOffset: byte * 8, bitSize: bits)
  }

  /// `inputHatSource`: an `EightWay` or `Table` byte and mask, or four `Directions` fields.
  private static func hat(
    _ path: String,
    _ members: [OrderedJSON.Member]
  ) throws -> [OrderedJSON.Member] {
    switch (members.first { $0.key == "encoding" })?.value {
    case .string("Directions")?:
      return try members.map { $0.key == "encoding" ? $0 : try field($0) }
    case .string("EightWay")?, .string("Table")?: return try masked(path, members)
    default: throw noMapping(path, "has no known encoding")
    }
  }

  /// `inputTrigger`: an 8-bit `byte`, and a `button` field.
  private static func trigger(_ member: OrderedJSON.Member) throws -> OrderedJSON {
    guard case .object(let members) = member.value else {
      throw noMapping("input.\(member.key)", "is not an object")
    }
    var converted = members
    if let byte = integer(members, "byte") {
      converted = addressed(converted, bitOffset: byte * 8, bitSize: 8)
    }
    return .object(try converted.map { $0.key == "button" ? try field($0) : $0 })
  }
}
