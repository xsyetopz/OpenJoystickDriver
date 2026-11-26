import Foundation

/// What a piece of record text is, for coloring.
enum RecordSyntaxKind: Equatable, Sendable {
  /// The name of a dictionary entry, between its `<key>` tags.
  case key
  /// A string value, between its `<string>` tags.
  case string
  /// An `<integer>` or `<real>` value, between its tags.
  case number
  /// `<true/>` or `<false/>`.
  case literal
  /// A tag, the XML declaration or the document type.
  case punctuation
  /// Spaces, tabs and line breaks between tags.
  case space
}

/// One run of the text.
///
/// The runs of a text, joined, give the text back.
struct RecordSyntaxToken: Equatable, Sendable {
  /// The kind of the run.
  let kind: RecordSyntaxKind
  /// The exact characters of the run.
  let text: String
  /// How many dictionaries and arrays enclose the token.
  ///
  /// A `<dict>` or `<array>` tag is not inside the container it opens or closes.
  let depth: Int
}

/// Text the tokenizer cannot read because its tags break the property list layout.
///
/// The text is a record's ``ControllerRecord/text``, which the catalog lays out as an XML property
/// list, so a failure means the catalog handed the Library text that is not one. The tokenizer
/// checks that tags open and close in order and that text sits only inside a value; it does not
/// check the property list grammar. It is a defect in the catalog's text, not a user's input.
struct RecordSyntaxError: Error, Equatable, CustomStringConvertible {
  /// The position in unicode scalars from the start of the text.
  let offset: Int
  /// Why the tokenizer rejects the text, in words.
  let reason: String

  /// The offset and the reason on one line.
  var description: String { "record text, scalar \(offset): \(reason)" }
}

/// Splits the XML property list text the catalog produces into colorable runs.
enum RecordSyntax {
  /// The elements whose text is a value or a name.
  private static let valueKinds: [String: RecordSyntaxKind] = [
    "key": .key, "string": .string, "integer": .number, "real": .number,
  ]

  /// Splits `text` into runs whose kinds the record view colors.
  ///
  /// - Parameter text: One XML property list.
  /// - Returns: The runs in text order, spaces included.
  /// - Throws: ``RecordSyntaxError`` for a tag that is not closed, a closing tag that does not
  ///   match the open one, text outside a value, or an element left open.
  static func tokens(in text: String) throws(RecordSyntaxError) -> [RecordSyntaxToken] {
    var lexer = Lexer(scalars: Array(text.unicodeScalars))
    while lexer.position < lexer.scalars.count {
      if lexer.scalars[lexer.position] == "<" {
        try lexer.readTag()
      } else {
        try lexer.readText()
      }
    }
    return try lexer.finish()
  }

  /// The reading position, the open elements and the tokens read so far.
  private struct Lexer {
    /// The text being read.
    let scalars: [Unicode.Scalar]
    /// The runs read so far.
    var tokens: [RecordSyntaxToken] = []
    /// The names of the open elements, innermost last.
    var open: [String] = []
    /// How many dictionaries and arrays are open.
    var containers = 0
    /// The index of the next scalar to read.
    var position = 0

    /// The text between `start` and `end`.
    func string(_ start: Int, _ end: Int) -> String {
      var view = String.UnicodeScalarView()
      view.append(contentsOf: scalars[start..<end])
      return String(view)
    }

    /// Reads the tag at the position as one token and updates the open elements.
    mutating func readTag() throws(RecordSyntaxError) {
      let start = position
      guard let close = scalars[position...].firstIndex(of: ">") else {
        throw RecordSyntaxError(offset: start, reason: "a tag is not closed")
      }
      position = close + 1
      let tag = string(start, position)
      let body = tag.dropFirst().dropLast()
      var kind = RecordSyntaxKind.punctuation
      var depth = containers
      if body.hasPrefix("?") || body.hasPrefix("!") {
        // The declaration and the document type open nothing.
      } else if body.hasPrefix("/") {
        try closeElement(named: String(body.dropFirst()), tag: tag, offset: start)
        depth = containers
      } else {
        kind = openElement(body)
      }
      tokens.append(RecordSyntaxToken(kind: kind, text: tag, depth: depth))
    }

    /// Closes the innermost element, which must be `name`.
    private mutating func closeElement(
      named name: String,
      tag: String,
      offset: Int
    ) throws(RecordSyntaxError) {
      guard open.last == name else {
        throw RecordSyntaxError(
          offset: offset,
          reason: "\(tag) does not close \(open.last.map { "<\($0)>" } ?? "an open tag")"
        )
      }
      open.removeLast()
      if name == "dict" || name == "array" { containers -= 1 }
    }

    /// Opens the element of a start or self-closing tag `body` and returns the kind of the tag.
    private mutating func openElement(_ body: Substring) -> RecordSyntaxKind {
      let selfClosing = body.hasSuffix("/")
      let name = String(
        (selfClosing ? body.dropLast() : body).prefix { !$0.isWhitespace }
      )
      if selfClosing {
        return name == "true" || name == "false" ? .literal : .punctuation
      }
      open.append(name)
      if name == "dict" || name == "array" { containers += 1 }
      return .punctuation
    }

    /// Reads the text up to the next tag as one token.
    mutating func readText() throws(RecordSyntaxError) {
      let start = position
      while position < scalars.count, scalars[position] != "<" { position += 1 }
      let run = string(start, position)
      if let name = open.last, let kind = RecordSyntax.valueKinds[name] {
        tokens.append(RecordSyntaxToken(kind: kind, text: run, depth: containers))
      } else if run.allSatisfy(\.isWhitespace) {
        tokens.append(RecordSyntaxToken(kind: .space, text: run, depth: containers))
      } else {
        throw RecordSyntaxError(offset: start, reason: "text outside a value")
      }
    }

    /// Returns the tokens once every element is closed and at least one token was read.
    func finish() throws(RecordSyntaxError) -> [RecordSyntaxToken] {
      if let name = open.last {
        throw RecordSyntaxError(offset: position, reason: "<\(name)> is not closed")
      }
      guard !tokens.isEmpty else { throw RecordSyntaxError(offset: 0, reason: "the text is empty") }
      return tokens
    }
  }
}
