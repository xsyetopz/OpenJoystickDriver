import Foundation

extension OrderedJSON {
  /// The members of an object, or nil for any other value.
  var members: [Member]? {
    guard case .object(let members) = self else { return nil }
    return members
  }

  /// The value of the member `key` of an object, or nil when this is not an object or has no
  /// such member.
  subscript(key: String) -> Self? {
    members?.first { $0.key == key }?.value
  }

  /// The text of a string value.
  var string: String? {
    guard case .string(let text) = self else { return nil }
    return text
  }

  /// A JSON integer: digits with an optional minus sign.
  ///
  /// A number written with a fraction or an exponent, such as `1.0` or `1e3`, a boolean, and a
  /// string are not.
  var integer: Int? {
    guard case .number(let text) = self else { return nil }
    return Int(text)
  }

  /// The value as `JSONSerialization` reads it, for code that reads typed fields.
  ///
  /// A number becomes an `NSNumber` there, so the result is never written back as record text.
  func foundationValue() throws -> Any {
    try JSONSerialization.jsonObject(
      with: Data(compact().utf8),
      options: .fragmentsAllowed
    )
  }

  /// Whether the two values are the same JSON value: object members in any order, and numbers by
  /// value at any length, so `8E-2` and `0.08` are the same and two integers of 40 digits that
  /// differ in the last digit are not.
  func hasSameValue(as other: Self) -> Bool {
    switch (self, other) {
    case (.object(let left), .object(let right)):
      guard left.count == right.count else { return false }
      return left.allSatisfy { member in
        other[member.key].map { member.value.hasSameValue(as: $0) } ?? false
      }
    case (.array(let left), .array(let right)):
      return left.count == right.count
        && zip(left, right).allSatisfy { $0.hasSameValue(as: $1) }
    case (.number(let left), .number(let right)):
      guard let first = Self.canonicalNumber(left), let second = Self.canonicalNumber(right) else {
        return left == right
      }
      return first == second
    default:
      return self == other
    }
  }

  /// The sign, significant digits and power of ten of a JSON number.
  private typealias CanonicalNumber = (negative: Bool, digits: String, exponent: Int)

  /// The sign, significant digits and power of ten of the JSON number `text`, with no leading or
  /// trailing zero in the digits, so numbers of the same value give the same result.
  ///
  /// Zero has no sign and no digits. Nil when the exponent does not fit an `Int`.
  private static func canonicalNumber(_ text: String) -> CanonicalNumber? {
    var rest = Substring(text)
    let negative = rest.hasPrefix("-")
    if negative { rest = rest.dropFirst() }
    let parts = rest.split(omittingEmptySubsequences: false) { $0 == "e" || $0 == "E" }
    let mantissa = parts[0].split(separator: ".", omittingEmptySubsequences: false)
    var exponent = 0
    if parts.count == 2 {
      guard let written = Int(parts[1]) else { return nil }
      exponent = written
    }
    let fraction = mantissa.count == 2 ? mantissa[1] : ""
    var digits = Substring(mantissa[0] + fraction).drop { $0 == "0" }
    guard !digits.isEmpty else { return (false, "", 0) }
    let (scaled, overflow) = exponent.subtractingReportingOverflow(fraction.count)
    guard !overflow else { return nil }
    exponent = scaled
    while digits.last == "0" {
      digits = digits.dropLast()
      exponent += 1
    }
    return (negative, String(digits), exponent)
  }
}
