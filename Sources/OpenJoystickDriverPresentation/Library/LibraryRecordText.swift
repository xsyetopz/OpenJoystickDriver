import Foundation

/// The Record section of a Library record, read once when the record is selected.
enum LibraryRecordDocument: Equatable {
  /// The record property list text.
  case text(LibraryRecordText)
  /// The tokenizer cannot read the document the catalog produced, with the reason. The section
  /// says the record text cannot be shown, and the reason goes to the log through `log`.
  case unreadable(RecordSyntaxError)

  /// Reads `document`.
  ///
  /// When the tokenizer cannot read it, the case is ``unreadable(_:)``.
  ///
  /// - Parameters:
  ///   - document: The record text the catalog produced.
  ///   - log: Receives the log line of an unreadable document; the default writes to standard
  ///     error.
  init(document: String, log: (String) -> Void = Self.writeToStandardError) {
    do throws(RecordSyntaxError) {
      self = .text(try LibraryRecordText(document: document))
    } catch {
      log(Self.logLine(error))
      self = .unreadable(error)
    }
  }

  /// The log line for a record text the tokenizer cannot read.
  static func logLine(_ error: RecordSyntaxError) -> String {
    "[Library] The record text cannot be shown: \(error.description)\n"
  }

  /// Writes `line` to standard error.
  static func writeToStandardError(_ line: String) {
    FileHandle.standardError.write(Data(line.utf8))
  }
}

/// The record property list of a Library record as the detail view shows it: the colored runs, and
/// the hexadecimal readings that sit beside the `vendorID` and `productID` lines.
///
/// ``copyText`` is the record document itself. The readings are not part of it, so selecting or
/// copying the shown text gives the property list.
struct LibraryRecordText: Equatable {
  /// The top-level entries that carry an identifier.
  static let identifierKeys: Set<String> = ["vendorID", "productID"]

  /// The hexadecimal reading of an identifier line.
  struct Reading: Equatable {
    /// The entry name, such as `vendorID`.
    let key: String
    /// The value in hexadecimal, such as `0x353D`.
    let hexadecimal: String
  }

  /// The document, exactly as the catalog holds it.
  let copyText: String
  /// The colored runs of the document, spaces included.
  let tokens: [RecordSyntaxToken]
  /// The lines of the document without line breaks, the last empty line left out.
  let lines: [String]
  /// The hexadecimal reading of the identifier on a line, by line index.
  let identifierReadings: [Int: Reading]

  /// Reads `document`, which the catalog produced, and works out the readings.
  ///
  /// - Parameter document: The record text the catalog produced.
  /// - Throws: ``RecordSyntaxError`` when the tokenizer cannot read the document.
  init(document: String) throws(RecordSyntaxError) {
    copyText = document
    tokens = try RecordSyntax.tokens(in: document)
    var split = document.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if split.last?.isEmpty == true { split.removeLast() }
    self.lines = split

    var readings: [Int: Reading] = [:]
    var line = 0
    var pendingKey: String?
    for token in tokens {
      switch token.kind {
      case .key:
        pendingKey = token.depth == 1 && Self.identifierKeys.contains(token.text) ? token.text : nil
      case .number:
        if let key = pendingKey, let value = UInt16(token.text) {
          readings[line] = Reading(key: key, hexadecimal: ProfileIdentifierInput.formatted(value))
        }
        pendingKey = nil
      case .punctuation where token.text.hasPrefix("</") || token.text == "<integer>":
        break
      case .space:
        break
      default:
        pendingKey = nil
      }
      line += token.text.filter { $0 == "\n" }.count
    }
    identifierReadings = readings
  }
}
