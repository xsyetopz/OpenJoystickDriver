public import Foundation

/// A JSON value that keeps the order of an object's members, and the text format of the
/// controller record files: two-space indent, `"key": value`, every object expanded, and an
/// array on one line when the line stays within 80 columns.
///
/// Every record text the app shows or writes comes from ``formatted()``, so it reads like the
/// bundled `Resources/Controllers` files, which `biome` formats the same way. An array that does
/// not fit on its line puts one item per line, except an array of numbers only, which fills each
/// line with as many numbers as fit, as `biome` does. A line's width is counted in columns: an
/// East Asian wide or fullwidth character and an emoji take two, a combining mark none.
public indirect enum OrderedJSON: Equatable, Sendable {
  /// An object, whose members keep their order.
  case object([Member])
  /// An array.
  case array([Self])
  /// A string.
  case string(String)
  /// A number as JSON text, such as `-1.5e3`.
  case number(String)
  /// A boolean.
  case bool(Bool)
  /// The `null` value.
  case null

  /// One member of an object.
  public struct Member: Equatable, Sendable {
    /// The member name.
    public let key: String
    /// The member value.
    public let value: OrderedJSON

    /// Creates a member from a name and a value.
    public init(key: String, value: OrderedJSON) {
      self.key = key
      self.value = value
    }
  }

  /// A JSON text that does not parse, or a value JSON cannot hold.
  public struct Problem: Error, Equatable, CustomStringConvertible, Sendable {
    /// Why JSON text or a Foundation value was refused.
    public enum Reason: Equatable, Sendable {
      /// The text starts with the UTF-8 byte order mark `EF BB BF`, which record files do not
      /// carry.
      case byteOrderMark
      /// The text starts with a UTF-16 byte order mark or has a zero byte in its first four
      /// bytes: JSON text starts with ASCII characters, which UTF-16 and UTF-32 write with zero
      /// bytes.
      case wideEncoding
      /// The bytes from ``Problem/offset`` are not UTF-8.
      case notUTF8
      /// An object names this member twice, byte for byte, so one of the values would be lost.
      case duplicateMember(String)
      /// An object names two members that are canonically equivalent Unicode text but differ in
      /// their scalars, such as U+00E9 and `e` with U+0301. Swift compares and hashes names by
      /// canonical equivalence, so a `[String: Any]` reader keeps only one of the two values.
      case equivalentMembers(String, String)
      /// The text breaks the JSON grammar, in words.
      case syntax(String)
      /// A Foundation value JSON cannot hold, in words.
      case notAJSONValue(String)
    }

    /// Why the text or value was refused.
    public let reason: Reason
    /// The byte of the text where the problem is; nil for a Foundation value.
    public let offset: Int?

    /// A message that names the reason and, when known, the byte offset.
    public var description: String {
      let message =
        switch reason {
        case .byteOrderMark:
          "the text starts with a byte order mark; save the file as UTF-8 without one"
        case .wideEncoding: "the text is UTF-16 or UTF-32; save the file as UTF-8"
        case .notUTF8: "the text is not UTF-8; save the file as UTF-8"
        case .duplicateMember(let key):
          "the member \(OrderedJSON.quoted(key)) appears twice in one object"
        case .equivalentMembers(let first, let second):
          "the members \(OrderedJSON.quoted(first)) and \(OrderedJSON.quoted(second)) have "
            + "different scalars but count as one name in Swift; write the name one way"
        case .syntax(let words), .notAJSONValue(let words): words
        }
      return offset.map { "JSON text, byte \($0): \(message)" } ?? message
    }
  }

  /// The widest line the array layout keeps on one line.
  static let lineWidth = 80
  /// The number of spaces of one indent level.
  static let indentWidth = 2

  // MARK: Foundation values

  /// `value`, a `JSONSerialization` object, laid out after `order`.
  ///
  /// At every depth, an object's members follow the members of the object at the same place in
  /// `order`, and the members `order` lacks come after them in sorted order; a key `order` names
  /// twice counts once. Array items take the order of the item at the same position. A number
  /// keeps the text of the number at the same place in `order` when that text reads as the same
  /// value, so `1e3` and `100.50` stay as written.
  ///
  /// The controller schema's property order is not a guide: Kit does not bundle the schemas. So a
  /// ``ControllerRecordDraft``, guided by ``recordKeys`` at the top level only, sorts every nested
  /// object. A patch merge works on ``OrderedJSON`` values and needs no guide.
  public init(foundation value: Any, order: Self? = nil) throws {
    switch value {
    case let dictionary as [String: Any]:
      var guide: [String: Self] = [:]
      var guided: [String] = []
      if case .object(let members)? = order {
        for member in members where guide[member.key] == nil {
          guided.append(member.key)
          guide[member.key] = member.value
        }
      }
      var remaining = dictionary
      var members: [Member] = []
      for key in guided {
        guard let child = remaining.removeValue(forKey: key) else { continue }
        members.append(Member(key: key, value: try Self(foundation: child, order: guide[key])))
      }
      for (key, child) in remaining.sorted(by: { $0.key < $1.key }) {
        members.append(Member(key: key, value: try Self(foundation: child)))
      }
      self = .object(members)
    case let list as [Any]:
      var guideItems: [Self] = []
      if case .array(let items)? = order { guideItems = items }
      var items: [Self] = []
      for (index, item) in list.enumerated() {
        items.append(
          try Self(foundation: item, order: index < guideItems.count ? guideItems[index] : nil)
        )
      }
      self = .array(items)
    case let text as String:
      self = .string(text)
    case is NSNull:
      self = .null
    // swiftlint:disable:next legacy_objc_type
    case let number as NSNumber:
      if CFGetTypeID(number) == CFBooleanGetTypeID() {
        self = .bool(number.boolValue)
      } else if case .number(let text)? = order, Self.reads(text, as: number) {
        self = .number(text)
      } else {
        self = .number(try Self.text(of: number))
      }
    default:
      throw Problem(reason: .notAJSONValue("\(type(of: value)) is not a JSON value"), offset: nil)
    }
  }

  /// Whether the JSON number `text` has the value of `number`.
  private static func reads(
    _ text: String,
    as number: NSNumber  // swiftlint:disable:this legacy_objc_type
  ) -> Bool {
    // swiftlint:disable:next legacy_objc_type
    if number is NSDecimalNumber { return Decimal(string: text) == number.decimalValue }
    if CFNumberIsFloatType(number) { return Double(text) == number.doubleValue }
    if let integer = Int64(text) { return integer == number.int64Value }
    return UInt64(text).map { $0 == number.uint64Value } ?? false
  }

  /// The JSON text of `number`: the digits of an integer or a decimal number, and the shortest
  /// text that reads back as the same `Double` for a floating-point one, with the exponent
  /// written `e-7` rather than `e-07`.
  private static func text(
    of number: NSNumber  // swiftlint:disable:this legacy_objc_type
  ) throws -> String {
    // swiftlint:disable:next legacy_objc_type
    guard CFNumberIsFloatType(number), !(number is NSDecimalNumber) else {
      return number.stringValue
    }
    guard number.doubleValue.isFinite else {
      throw Problem(
        reason: .notAJSONValue("JSON cannot hold a number that is not finite"),
        offset: nil
      )
    }
    let text = "\(number.doubleValue)"
    guard let mark = text.firstIndex(of: "e") else { return text }
    var exponent = text[text.index(after: mark)...]
    let negative = exponent.first == "-"
    exponent = exponent.drop { $0 == "+" || $0 == "-" }.drop { $0 == "0" }
    return String(text[...mark]) + (negative ? "-" : "")
      + (exponent.isEmpty ? "0" : String(exponent))
  }

  // MARK: Parsing

  /// The value in `data`, a UTF-8 JSON document without a byte order mark.
  ///
  /// A member name that appears twice in one object is refused, because a reader keeps only one of
  /// its values; so are two names that differ in their scalars only by canonical equivalence,
  /// because a `[String: Any]` reader merges them.
  public static func parse(_ data: Data) throws -> Self {
    let bytes = [UInt8](data)
    try requireUTF8(bytes)
    var parser = Parser(bytes: bytes)
    parser.skipSpace()
    let value = try parser.value()
    parser.skipSpace()
    guard parser.atEnd else { throw parser.problem("unexpected text after the value") }
    return value
  }

  /// Refuses text that is not plain UTF-8: a byte order mark, UTF-16 or UTF-32 text, or bytes that
  /// do not decode as UTF-8.
  ///
  /// A zero byte after the first four is a ``Problem/Reason/syntax`` problem, because JSON text
  /// cannot carry one, not even in a string.
  public static func requireUTF8(_ data: Data) throws { try requireUTF8([UInt8](data)) }

  /// Throws a ``Problem`` unless `bytes` is UTF-8 without a byte order mark and without a zero
  /// byte.
  private static func requireUTF8(_ bytes: [UInt8]) throws {
    if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
      throw Problem(reason: .byteOrderMark, offset: 0)
    }
    if bytes.starts(with: [0xFE, 0xFF]) || bytes.starts(with: [0xFF, 0xFE]) {
      throw Problem(reason: .wideEncoding, offset: 0)
    }
    if let zero = bytes.prefix(4).firstIndex(of: 0) {
      throw Problem(reason: .wideEncoding, offset: zero)
    }
    var iterator = bytes.makeIterator()
    var decoder = UTF8()
    var offset = 0
    while true {
      switch decoder.decode(&iterator) {
      case .scalarValue(let scalar):
        if scalar == "\0" { throw Problem(reason: .syntax(zeroByteWords), offset: offset) }
        offset += UTF8.width(scalar)
      case .emptyInput: return
      case .error: throw Problem(reason: .notUTF8, offset: offset)
      }
    }
  }

  /// The `syntax` message for a zero byte in the text.
  static let zeroByteWords = "a zero byte, which JSON text cannot carry"

  // MARK: Formatting

  /// The record file text, ending in a newline.
  public func formatted() -> String {
    var output = ""
    write(into: &output, indent: 0, prefix: 0, suffix: 0)
    output += "\n"
    return output
  }

  /// The value on one line without spaces, such as `{"a":[1,2]}`, and without a newline.
  public func compact() -> String {
    switch self {
    case .object(let members):
      let parts = members.map { Self.quoted($0.key) + ":" + $0.value.compact() }
      return "{" + parts.joined(separator: ",") + "}"
    case .array(let items): return "[" + items.map { $0.compact() }.joined(separator: ",") + "]"
    case .string(let text): return Self.quoted(text)
    case .number(let text): return text
    case .bool(let flag): return flag ? "true" : "false"
    case .null: return "null"
    }
  }

  /// ``formatted()`` as UTF-8.
  public func formattedData() -> Data { Data(formatted().utf8) }

  /// Writes the value. `prefix` is the columns already used on the line before the value (the
  /// indent and the key), `suffix` the columns a trailing comma needs.
  private func write(into output: inout String, indent: Int, prefix: Int, suffix: Int) {
    switch self {
    case .object(let members):
      guard !members.isEmpty else {
        output += "{}"
        return
      }
      output += "{\n"
      let inner = indent + Self.indentWidth
      for (index, member) in members.enumerated() {
        let key = Self.quoted(member.key) + ": "
        let last = index == members.count - 1
        output += String(repeating: " ", count: inner) + key
        member.value.write(
          into: &output,
          indent: inner,
          prefix: inner + Self.columns(key),
          suffix: last ? 0 : 1
        )
        output += last ? "\n" : ",\n"
      }
      output += String(repeating: " ", count: indent) + "}"
    case .array(let items):
      guard !items.isEmpty else {
        output += "[]"
        return
      }
      if let flat = flatText, prefix + Self.columns(flat) + suffix <= Self.lineWidth {
        output += flat
        return
      }
      output += "[\n"
      let inner = indent + Self.indentWidth
      let numbers = items.compactMap { item -> String? in
        if case .number(let text) = item { return text }
        return nil
      }
      if numbers.count == items.count {
        Self.fill(numbers, into: &output, indent: inner)
      } else {
        for (index, item) in items.enumerated() {
          let last = index == items.count - 1
          output += String(repeating: " ", count: inner)
          item.write(into: &output, indent: inner, prefix: inner, suffix: last ? 0 : 1)
          output += last ? "\n" : ",\n"
        }
      }
      output += String(repeating: " ", count: indent) + "]"
    default:
      output += flatText ?? ""
    }
  }

  /// Writes `numbers` as `biome` fills an array of numbers: each number, with its comma, goes on
  /// the current line when the line stays within 80 columns, and starts a line otherwise.
  private static func fill(_ numbers: [String], into output: inout String, indent: Int) {
    output += String(repeating: " ", count: indent)
    var column = indent
    for (index, number) in numbers.enumerated() {
      let text = index == numbers.count - 1 ? number : number + ","
      let width = columns(text)
      if index > 0 {
        if column + 1 + width <= lineWidth {
          output += " "
          column += 1
        } else {
          output += "\n" + String(repeating: " ", count: indent)
          column = indent
        }
      }
      output += text
      column += width
    }
    output += "\n"
  }

  /// The one-line text of a value with no filled object in it; nil otherwise.
  private var flatText: String? {
    switch self {
    case .object(let members): return members.isEmpty ? "{}" : nil
    case .array(let items):
      guard !items.isEmpty else { return "[]" }
      var parts: [String] = []
      for item in items {
        guard let part = item.flatText else { return nil }
        parts.append(part)
      }
      return "[" + parts.joined(separator: ", ") + "]"
    case .string(let text): return Self.quoted(text)
    case .number(let text): return text
    case .bool(let flag): return flag ? "true" : "false"
    case .null: return "null"
    }
  }

  /// The columns `text` takes in a monospaced line, as `biome` counts them: two for an East
  /// Asian wide or fullwidth character and for an emoji shown as an emoji, none for a combining
  /// mark, a format character other than the soft hyphen, and a Hangul medial vowel or final
  /// consonant, and one for any other character.
  static func columns(_ text: String) -> Int {
    text.unicodeScalars.reduce(0) { $0 + columns(of: $1) }
  }

  /// The number of columns a scalar takes: 0 for a combining or format mark, 2 for a wide character
  /// or an emoji, otherwise 1.
  private static func columns(of scalar: Unicode.Scalar) -> Int {
    let value = scalar.value
    switch scalar.properties.generalCategory {
    case .nonspacingMark, .enclosingMark: return 0
    case .format where value != 0xAD: return 0
    default: break
    }
    if (0x1160...0x11FF).contains(value) { return 0 }
    if scalar.properties.isEmojiPresentation { return 2 }
    return wideRanges.contains { $0.contains(value) } ? 2 : 1
  }

  /// The East Asian Wide and Fullwidth blocks of Unicode outside the emoji: Hangul initial
  /// consonants, CJK punctuation, kana, ideographs, Yi, Hangul syllables, fullwidth forms, and
  /// the supplementary ideographic planes.
  private static let wideRanges: [ClosedRange<UInt32>] = [
    0x1100...0x115F, 0x2329...0x232A, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF,
    0x4E00...0x9FFF, 0xA000...0xA4CF, 0xA960...0xA97F, 0xAC00...0xD7A3, 0xF900...0xFAFF,
    0xFE10...0xFE19, 0xFE30...0xFE6F, 0xFF00...0xFF60, 0xFFE0...0xFFE6, 0x16FE0...0x16FE4,
    0x17000...0x18CFF, 0x1B000...0x1B2FF, 0x1F200...0x1F2FF, 0x20000...0x2FFFD,
    0x30000...0x3FFFD,
  ]

  /// `text` as a JSON string literal with its quotes and escapes.
  static func quoted(_ text: String) -> String {
    var output = "\""
    for scalar in text.unicodeScalars {
      switch scalar {
      case "\"": output += "\\\""
      case "\\": output += "\\\\"
      case "\n": output += "\\n"
      case "\r": output += "\\r"
      case "\t": output += "\\t"
      case "\u{08}": output += "\\b"
      case "\u{0C}": output += "\\f"
      case _ where scalar.value < 0x20: output += unsafe String(format: "\\u%04x", scalar.value)
      default: output.unicodeScalars.append(scalar)
      }
    }
    return output + "\""
  }
}
