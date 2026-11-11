import Foundation

/// What a piece of record JSON text is, for coloring.
enum JSONSyntaxKind: Equatable, Sendable {
  /// An object member name, with its quotes.
  case key
  /// A string value, with its quotes.
  case string
  /// A number value.
  case number
  /// `true`, `false` or `null`.
  case literal
  /// `{ } [ ] , :`
  case punctuation
  /// Spaces and line breaks.
  case space
}

/// One run of the text.
///
/// The runs of a text, joined, give the text back.
struct JSONSyntaxToken: Equatable, Sendable {
  /// The kind of the run.
  let kind: JSONSyntaxKind
  /// The exact characters of the run.
  let text: String
  /// How many objects and arrays enclose the token.
  ///
  /// A bracket is not inside the container it opens or closes.
  let depth: Int
}

/// Text the tokenizer cannot read because it breaks the JSON grammar.
///
/// The text is a record's ``ControllerRecord/text``, which the catalog lays out with
/// ``OrderedJSON/formatted()``, so a failure means the catalog handed the Library text that is not
/// one standard JSON value; the tokenizer checks the grammar only, not duplicate member names or
/// the encoding. It is a defect in the catalog's text, not a user's input.
struct JSONSyntaxError: Error, Equatable, CustomStringConvertible {
  /// The position in unicode scalars from the start of the text.
  let offset: Int
  /// Why the grammar rejects the text, in words.
  let reason: String

  /// The offset and the reason on one line.
  var description: String { "JSON text, scalar \(offset): \(reason)" }
}

/// Splits the JSON text the app produces into colorable runs.
///
/// It reads the format of ``OrderedJSON/formatted()``: one standard JSON value, any spacing. It
/// follows the JSON grammar, so a token where JSON does not allow it (`[1 2]`, `{,}`, `{"a" 1}`,
/// a trailing comma, a second top-level value) or a container left open or closed twice throws.
enum JSONSyntax {
  /// Splits `text` into runs whose kinds the record view colors.
  ///
  /// - Parameter text: One JSON value in any spacing, as ``OrderedJSON/formatted()`` lays it out.
  /// - Returns: The runs in text order, spaces included.
  /// - Throws: ``JSONSyntaxError`` when the text breaks the JSON grammar.
  static func tokens(in text: String) throws(JSONSyntaxError) -> [JSONSyntaxToken] {
    var scanner = Scanner(scalars: Array(text.unicodeScalars))
    return try scanner.run()
  }

  /// What the grammar allows at the scanner's position.
  private enum Expectation: Equatable {
    /// A value: at the start, after `:`, or after `,` in an array.
    case value
    /// A value or `]`, after `[`.
    case valueOrClose
    /// A member name, after `,` in an object.
    case key
    /// A member name or `}`, after `{`.
    case keyOrClose
    /// `:`, after a member name.
    case colon
    /// `,` or the bracket that closes the container, after a value inside it.
    case commaOrClose
    /// Nothing but space, after the top-level value.
    case end
  }

  /// The state of one pass over the text: the position, the runs found and the open containers.
  private struct Scanner {
    /// The scalars of the text.
    let scalars: [Unicode.Scalar]
    /// The index in ``scalars`` of the next scalar to read.
    var position = 0
    /// The runs found so far.
    var tokens: [JSONSyntaxToken] = []
    /// `true` for an object, `false` for an array.
    var containers: [Bool] = []
    /// What the grammar allows at ``position``.
    var expectation = Expectation.value

    /// Creates a scanner at the start of `scalars`.
    init(scalars: [Unicode.Scalar]) { self.scalars = scalars }

    /// Returns the error for `reason`, at `offset` or, when nil, at ``position``.
    func failure(_ reason: String, at offset: Int? = nil) -> JSONSyntaxError {
      JSONSyntaxError(offset: offset ?? position, reason: reason)
    }

    /// Whether the grammar allows a value at ``position``.
    var expectsValue: Bool { expectation == .value || expectation == .valueOrClose }

    /// Reads the whole text and returns its runs.
    ///
    /// - Throws: ``JSONSyntaxError`` at the first scalar the grammar does not allow, or when a
    ///   container is left open or the text holds no value.
    mutating func run() throws(JSONSyntaxError) -> [JSONSyntaxToken] {
      while position < scalars.count {
        let scalar = scalars[position]
        switch scalar {
        case " ", "\n", "\r", "\t":
          let start = position
          while position < scalars.count, [" ", "\n", "\r", "\t"].contains(scalars[position]) {
            position += 1
          }
          emit(.space, from: start)
        case "{", "[":
          guard expectsValue else { throw unexpected(scalar) }
          emit(.punctuation, from: position, length: 1)
          containers.append(scalar == "{")
          expectation = scalar == "{" ? .keyOrClose : .valueOrClose
          position += 1
        case "}", "]":
          let isObject = scalar == "}"
          guard containers.last == isObject,
            expectation == .commaOrClose || expectation == (isObject ? .keyOrClose : .valueOrClose)
          else { throw unexpected(scalar) }
          containers.removeLast()
          emit(.punctuation, from: position, length: 1)
          position += 1
          endValue()
        case ",":
          guard expectation == .commaOrClose, let isObject = containers.last else {
            throw unexpected(scalar)
          }
          expectation = isObject ? .key : .value
          emit(.punctuation, from: position, length: 1)
          position += 1
        case ":":
          guard expectation == .colon else { throw unexpected(scalar) }
          expectation = .value
          emit(.punctuation, from: position, length: 1)
          position += 1
        case "\"":
          let isKey = expectation == .key || expectation == .keyOrClose
          guard isKey || expectsValue else { throw unexpected(scalar) }
          let start = position
          try string()
          emit(isKey ? .key : .string, from: start)
          if isKey { expectation = .colon } else { endValue() }
        case "t", "f", "n":
          guard expectsValue else { throw unexpected(scalar) }
          let start = position
          try literal()
          emit(.literal, from: start)
          endValue()
        case "-", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
          guard expectsValue else { throw unexpected(scalar) }
          let start = position
          try number()
          emit(.number, from: start)
          endValue()
        default:
          throw unexpected(scalar)
        }
      }
      guard containers.isEmpty else { throw failure("a container is not closed") }
      guard expectation == .end else { throw failure("the text holds no value") }
      return tokens
    }

    /// The failure for `scalar` where the grammar does not allow it.
    func unexpected(_ scalar: Unicode.Scalar) -> JSONSyntaxError {
      failure("unexpected \(String(scalar).debugDescription) where JSON expects \(expected)")
    }

    /// The words that say what the grammar expects, for an error message.
    var expected: String {
      switch expectation {
      case .value: "a value"
      case .valueOrClose: "a value or ]"
      case .key: "a member name"
      case .keyOrClose: "a member name or }"
      case .colon: ":"
      case .commaOrClose: containers.last == true ? ", or }" : ", or ]"
      case .end: "the end of the text"
      }
    }

    /// A value ended: the container that holds it takes a comma or its closing bracket next.
    mutating func endValue() { expectation = containers.isEmpty ? .end : .commaOrClose }

    /// Appends the run from `start` to `length` scalars later, or to ``position`` when nil.
    mutating func emit(_ kind: JSONSyntaxKind, from start: Int, length: Int? = nil) {
      let end = length.map { start + $0 } ?? position
      var text = String.UnicodeScalarView()
      text.append(contentsOf: scalars[start..<end])
      tokens.append(JSONSyntaxToken(kind: kind, text: String(text), depth: containers.count))
    }

    /// Reads a string with its quotes, from the opening quote to the closing one.
    ///
    /// - Throws: ``JSONSyntaxError`` for a control character, an unknown or short escape, or a
    ///   string that is not closed.
    mutating func string() throws(JSONSyntaxError) {
      position += 1
      while position < scalars.count {
        let scalar = scalars[position]
        if scalar == "\"" {
          position += 1
          return
        }
        if scalar.value < 0x20 { throw failure("a control character in a string") }
        if scalar == "\\" {
          position += 1
          guard position < scalars.count else { break }
          switch scalars[position] {
          case "\"", "\\", "/", "b", "f", "n", "r", "t":
            position += 1
          case "u":
            position += 1
            for _ in 0..<4 {
              guard position < scalars.count, scalars[position].properties.isASCIIHexDigit else {
                throw failure("a \\u escape needs four hexadecimal digits")
              }
              position += 1
            }
          default:
            throw failure("an unknown escape \\\(scalars[position])")
          }
        } else {
          position += 1
        }
      }
      throw failure("a string is not closed")
    }

    /// Reads `true`, `false` or `null`.
    ///
    /// - Throws: ``JSONSyntaxError`` when none of the three words starts at ``position``.
    mutating func literal() throws(JSONSyntaxError) {
      for word in ["true", "false", "null"] {
        let wanted = Array(word.unicodeScalars)
        if position + wanted.count <= scalars.count,
          Array(scalars[position..<position + wanted.count]) == wanted
        {
          position += wanted.count
          return
        }
      }
      throw failure("expected true, false or null")
    }

    /// Reads a run of decimal digits and returns how many it read.
    mutating func digits() -> Int {
      let begin = position
      while position < scalars.count, ("0"..."9").contains(scalars[position]) { position += 1 }
      return position - begin
    }

    /// Reads a number: an optional minus sign, an integer part, and optional fraction and exponent.
    ///
    /// - Throws: ``JSONSyntaxError`` when the minus sign, the decimal point or the exponent has no
    ///   digits after it.
    mutating func number() throws(JSONSyntaxError) {
      if scalars[position] == "-" { position += 1 }
      if position < scalars.count, scalars[position] == "0" {
        position += 1
      } else if digits() == 0 {
        throw failure("a minus sign needs digits")
      }
      if position < scalars.count, scalars[position] == "." {
        position += 1
        guard digits() > 0 else { throw failure("a decimal point needs digits") }
      }
      if position < scalars.count, scalars[position] == "e" || scalars[position] == "E" {
        position += 1
        if position < scalars.count, scalars[position] == "+" || scalars[position] == "-" {
          position += 1
        }
        guard digits() > 0 else { throw failure("an exponent needs digits") }
      }
    }
  }
}
