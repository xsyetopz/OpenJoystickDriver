import Foundation

extension OrderedJSON {
  /// A recursive-descent parser over bytes that ``OrderedJSON/parse(_:)`` checked are UTF-8.
  struct Parser {
    /// The UTF-8 text to parse.
    let bytes: [UInt8]
    /// The offset of the next byte to read.
    var position = 0

    /// Creates a parser at the start of `bytes`.
    init(bytes: [UInt8]) { self.bytes = bytes }

    /// Whether every byte has been read.
    var atEnd: Bool { position >= bytes.count }

    /// The text of `bytes`, which are UTF-8 because ``OrderedJSON/parse(_:)`` checked the whole
    /// text before parsing.
    static func text(_ bytes: some Collection<UInt8>) -> String {
      // swiftlint:disable:next optional_data_string_conversion
      String(decoding: bytes, as: UTF8.self)
    }

    /// A syntax problem with `message` at the current offset.
    func problem(_ message: String) -> Problem {
      Problem(reason: .syntax(message), offset: position)
    }

    /// Whether the next byte is the ASCII `character`.
    func peek(_ character: Character) -> Bool {
      position < bytes.count && bytes[position] == character.asciiValue
    }

    /// Moves past JSON whitespace: space, line feed, carriage return and tab.
    mutating func skipSpace() {
      while position < bytes.count, [0x20, 0x0A, 0x0D, 0x09].contains(bytes[position]) {
        position += 1
      }
    }

    /// Reads the JSON value at the current offset.
    /// - Throws: ``OrderedJSON/Problem`` for text that is not a JSON value.
    mutating func value() throws -> OrderedJSON {
      guard position < bytes.count else { throw problem("the text ends early") }
      switch bytes[position] {
      case UInt8(ascii: "{"): return try object()
      case UInt8(ascii: "["): return try array()
      case UInt8(ascii: "\""): return .string(try string())
      case UInt8(ascii: "t"):
        try literal("true")
        return .bool(true)
      case UInt8(ascii: "f"):
        try literal("false")
        return .bool(false)
      case UInt8(ascii: "n"):
        try literal("null")
        return .null
      default: return try number()
      }
    }

    /// Reads the exact word `word`, which is `true`, `false` or `null`.
    /// - Throws: ``OrderedJSON/Problem`` when the text differs.
    mutating func literal(_ word: String) throws {
      let expected = Array(word.utf8)
      guard bytes.count - position >= expected.count,
        Array(bytes[position..<position + expected.count]) == expected
      else { throw problem("expected \(word)") }
      position += expected.count
    }

    /// Reads an object and keeps its members in order.
    /// - Throws: ``OrderedJSON/Problem`` for a syntax error, and for a member name that repeats or
    ///   that equals an earlier name under Unicode canonical equivalence.
    mutating func object() throws -> OrderedJSON {
      position += 1
      var members: [Member] = []
      // The first spelling of each name, found by the name as Swift compares it (canonical
      // equivalence) and told from a later spelling by its Unicode scalars.
      var names: [String: String] = [:]
      skipSpace()
      if peek("}") {
        position += 1
        return .object([])
      }
      while true {
        skipSpace()
        guard peek("\"") else { throw problem("expected a member name") }
        let start = position
        let key = try string()
        if let first = names[key] {
          throw Problem(
            reason: first.unicodeScalars.elementsEqual(key.unicodeScalars)
              ? .duplicateMember(key) : .equivalentMembers(first, key),
            offset: start
          )
        }
        names[key] = key
        skipSpace()
        guard peek(":") else { throw problem("expected :") }
        position += 1
        skipSpace()
        members.append(Member(key: key, value: try value()))
        skipSpace()
        if peek(",") {
          position += 1
        } else if peek("}") {
          position += 1
          return .object(members)
        } else {
          throw problem("expected , or }")
        }
      }
    }

    /// Reads an array and keeps its elements in order.
    /// - Throws: ``OrderedJSON/Problem`` for a syntax error.
    mutating func array() throws -> OrderedJSON {
      position += 1
      var items: [OrderedJSON] = []
      skipSpace()
      if peek("]") {
        position += 1
        return .array([])
      }
      while true {
        skipSpace()
        items.append(try value())
        skipSpace()
        if peek(",") {
          position += 1
        } else if peek("]") {
          position += 1
          return .array(items)
        } else {
          throw problem("expected , or ]")
        }
      }
    }

    /// Reads a string and decodes its escapes.
    /// - Throws: ``OrderedJSON/Problem`` for a control character, an unknown escape, a bad `\u`
    ///   escape, or text that ends inside the string.
    mutating func string() throws -> String {
      position += 1
      var text = ""
      var run: [UInt8] = []
      // ``OrderedJSON/parse(_:)`` checked that the bytes are UTF-8.
      func flush() {
        text += Self.text(run)
        run.removeAll()
      }
      while position < bytes.count {
        let byte = bytes[position]
        if byte == UInt8(ascii: "\"") {
          position += 1
          flush()
          return text
        }
        if byte < 0x20 { throw problem("a control character in a string") }
        guard byte == UInt8(ascii: "\\") else {
          run.append(byte)
          position += 1
          continue
        }
        flush()
        position += 1
        guard position < bytes.count else { break }
        let escape = bytes[position]
        position += 1
        switch escape {
        case UInt8(ascii: "\""): text += "\""
        case UInt8(ascii: "\\"): text += "\\"
        case UInt8(ascii: "/"): text += "/"
        case UInt8(ascii: "b"): text += "\u{08}"
        case UInt8(ascii: "f"): text += "\u{0C}"
        case UInt8(ascii: "n"): text += "\n"
        case UInt8(ascii: "r"): text += "\r"
        case UInt8(ascii: "t"): text += "\t"
        case UInt8(ascii: "u"): text.unicodeScalars.append(try unicodeEscape())
        default: throw problem("an unknown escape")
        }
      }
      throw problem("the text ends inside a string")
    }

    /// Reads four hexadecimal digits as one UTF-16 code unit.
    /// - Throws: ``OrderedJSON/Problem`` when four hexadecimal digits do not follow.
    mutating func hexUnit() throws -> UInt32 {
      guard bytes.count - position >= 4,
        bytes[position..<position + 4].allSatisfy({ Character(Unicode.Scalar($0)).isHexDigit }),
        let unit = UInt32(
          Self.text(bytes[position..<position + 4]),
          radix: 16
        )
      else { throw problem("expected four hexadecimal digits") }
      position += 4
      return unit
    }

    /// Reads the code point of a `\u` escape after its `\u` has been read; a high surrogate takes
    /// the low surrogate of the escape that follows it.
    /// - Throws: ``OrderedJSON/Problem`` for a high surrogate without a low one and for a lone low
    ///   surrogate.
    mutating func unicodeEscape() throws -> Unicode.Scalar {
      let first = try hexUnit()
      if (0xD800...0xDBFF).contains(first) {
        guard peek("\\"), position + 1 < bytes.count, bytes[position + 1] == UInt8(ascii: "u")
        else {
          throw problem("a high surrogate without a low surrogate")
        }
        position += 2
        let second = try hexUnit()
        guard (0xDC00...0xDFFF).contains(second),
          let scalar = Unicode.Scalar(0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00))
        else { throw problem("a high surrogate without a low surrogate") }
        return scalar
      }
      guard let scalar = Unicode.Scalar(first) else { throw problem("a lone low surrogate") }
      return scalar
    }

    /// Moves past ASCII digits and returns how many it passed.
    mutating func digits() -> Int {
      let begin = position
      while position < bytes.count, (0x30...0x39).contains(bytes[position]) { position += 1 }
      return position - begin
    }

    /// Reads a number and keeps its text as written.
    /// - Throws: ``OrderedJSON/Problem`` when the text is not a JSON number.
    mutating func number() throws -> OrderedJSON {
      let start = position
      if peek("-") { position += 1 }
      if peek("0") {
        position += 1
      } else if digits() == 0 {
        throw problem("expected a value")
      }
      if peek(".") {
        position += 1
        guard digits() > 0 else { throw problem("expected digits after the decimal point") }
      }
      if peek("e") || peek("E") {
        position += 1
        if peek("+") || peek("-") { position += 1 }
        guard digits() > 0 else { throw problem("expected digits in the exponent") }
      }
      return .number(Self.text(bytes[start..<position]))
    }
  }
}
