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
    let scalars = Array(text.unicodeScalars)
    var tokens: [RecordSyntaxToken] = []
    var open: [String] = []
    var containers = 0
    var position = 0

    func string(_ start: Int, _ end: Int) -> String {
      var view = String.UnicodeScalarView()
      view.append(contentsOf: scalars[start..<end])
      return String(view)
    }

    while position < scalars.count {
      let start = position
      if scalars[position] == "<" {
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
          let name = String(body.dropFirst())
          guard open.last == name else {
            throw RecordSyntaxError(
              offset: start,
              reason: "\(tag) does not close \(open.last.map { "<\($0)>" } ?? "an open tag")"
            )
          }
          open.removeLast()
          if name == "dict" || name == "array" {
            containers -= 1
            depth = containers
          }
        } else {
          let selfClosing = body.hasSuffix("/")
          let name = String(
            (selfClosing ? body.dropLast() : body).prefix { !$0.isWhitespace }
          )
          if selfClosing {
            if name == "true" || name == "false" { kind = .literal }
          } else {
            open.append(name)
            if name == "dict" || name == "array" { containers += 1 }
          }
        }
        tokens.append(RecordSyntaxToken(kind: kind, text: tag, depth: depth))
      } else {
        while position < scalars.count, scalars[position] != "<" { position += 1 }
        let run = string(start, position)
        if let name = open.last, let kind = valueKinds[name] {
          tokens.append(RecordSyntaxToken(kind: kind, text: run, depth: containers))
        } else if run.allSatisfy(\.isWhitespace) {
          tokens.append(RecordSyntaxToken(kind: .space, text: run, depth: containers))
        } else {
          throw RecordSyntaxError(offset: start, reason: "text outside a value")
        }
      }
    }
    if let name = open.last {
      throw RecordSyntaxError(offset: position, reason: "<\(name)> is not closed")
    }
    guard !tokens.isEmpty else { throw RecordSyntaxError(offset: 0, reason: "the text is empty") }
    return tokens
  }
}
