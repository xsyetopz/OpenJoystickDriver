import Foundation

/// Which controllers of a family a startup write in its protocol description is for.
///
/// Records never carry a condition: a record's write is for that record.
public struct StartupWriteCondition: Equatable, Sendable {
  /// A rule on one enumeration parameter of the controller's record.
  public struct Rule: Equatable, Sendable {
    /// The name of the enumeration parameter the rule tests.
    public let parameter: String
    /// The parameter values the rule lists.
    public let values: [String]
    /// True for `isNot`, which also matches a controller that leaves the parameter unset.
    public let negated: Bool

    /// Whether the rule holds for a controller whose record sets `parameters`.
    func matches(_ parameters: ProtocolParameters) -> Bool {
      let value = parameters.enumerationValue(parameter)
      let listed = value.map(values.contains) ?? false
      return listed != negated
    }
  }

  /// The stored variants the write is sent on; nil for every variant.
  public let variants: [PhysicalProtocolVariantID]?
  /// The rule on a record parameter that the controller must satisfy; nil for none.
  public let rule: Rule?

  /// The condition that every controller satisfies.
  public static let always = Self(variants: nil, rule: nil)

  /// Creates a condition from the variants and the parameter rule.
  public init(variants: [PhysicalProtocolVariantID]? = nil, rule: Rule? = nil) {
    self.variants = variants
    self.rule = rule
  }

  /// Whether the condition holds for every controller.
  public var isAlways: Bool { variants == nil && rule == nil }

  /// Whether a controller on `variant` whose record sets `parameters` receives the write.
  ///
  /// A controller with no stored variant matches only a write that names none.
  public func matches(
    variant: PhysicalProtocolVariantID?,
    parameters: ProtocolParameters
  ) -> Bool {
    if let variants, !(variant.map(variants.contains) ?? false) { return false }
    return rule?.matches(parameters) ?? true
  }
}

extension CodingUserInfoKey {
  /// Set while a protocol description decodes: only a description's startup writes may carry
  /// a `variants` or `when` condition.
  static let startupConditionsAllowed: CodingUserInfoKey = {
    let name = "OpenJoystickDriver.startupConditionsAllowed"
    guard let key = CodingUserInfoKey(rawValue: name) else {
      preconditionFailure("CodingUserInfoKey accepts every raw value")
    }
    return key
  }()
}

extension StartupWriteCondition {
  /// Reads `variants` and `when` from a startup write; both are absent in a record.
  static func decode(
    from container: KeyedDecodingContainer<DocumentKey>,
    decoder: any Decoder
  ) throws -> Self {
    let hasVariants = container.contains(DocumentKey("variants"))
    let hasWhen = container.contains(DocumentKey("when"))
    guard hasVariants || hasWhen else { return .always }
    guard decoder.userInfo[.startupConditionsAllowed] as? Bool == true else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath,
          debugDescription: "variants and when belong to a protocol description"
        )
      )
    }
    var variants: [PhysicalProtocolVariantID]?
    if let names = try container.decodeOptional([String].self, for: "variants") {
      let parsed = names.compactMap(PhysicalProtocolVariantID.init(rawValue:))
      guard (1...8).contains(names.count), parsed.count == names.count,
        Set(parsed).count == parsed.count
      else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("variants")],
            debugDescription: "variants lists 1...8 distinct variant names"
          )
        )
      }
      variants = parsed
    }
    var rule: Rule?
    if let when = try container.decodeOptional(When.self, for: "when") { rule = when.rule }
    return Self(variants: variants, rule: rule)
  }

  /// The JSON object of a `when` key.
  private struct When: Decodable {
    /// The rule the object states.
    let rule: Rule

    /// Decodes `parameter` and exactly one of `is` or `isNot`; an unknown key, an unknown
    /// parameter, or a value count outside 1...16 is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["parameter", "is", "isNot"])
      let parameter = try container.decode(String.self, for: "parameter")
      let positive = try container.decodeOptional([String].self, for: "is")
      let negative = try container.decodeOptional([String].self, for: "isNot")
      guard (positive == nil) != (negative == nil),
        let values = positive ?? negative, (1...16).contains(values.count),
        ProtocolParameters.enumerationNames.contains(parameter)
      else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription:
              "when names an enumeration parameter and exactly one of is or isNot, 1...16 values"
          )
        )
      }
      rule = Rule(parameter: parameter, values: values, negated: negative != nil)
    }
  }
}
