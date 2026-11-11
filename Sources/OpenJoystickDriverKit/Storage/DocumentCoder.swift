import Foundation

/// A stored document that is not an XML property list, or that holds a value no schema type
/// accepts.
public struct DocumentCoderError: Error, Equatable, Sendable, CustomStringConvertible {
  /// What the file holds in place of an XML property list, or the value that is refused.
  public enum Reason: Equatable, Sendable {
    /// A binary property list.
    case binary
    /// JSON text.
    case json
    /// Neither an XML property list nor JSON, such as an old-style property list or other text.
    case notXML
    /// A `date` or `data` value at `keyPath`.
    case unsupportedValue(keyPath: String, kind: String)
  }

  /// The file, as the reader names it.
  public let file: String
  /// Why the file is refused.
  public let reason: Reason
  /// The error code of the refusal.
  public let code = ErrorCode.invalidDocumentForm

  /// The file and the reason, in words.
  public var description: String {
    switch reason {
    case .binary: "\(file) is a binary property list; save it as an XML property list"
    case .json: "\(file) holds JSON text; save it as an XML property list"
    case .notXML: "\(file) is not an XML property list"
    case .unsupportedValue(let keyPath, let kind):
      "\(file): \(keyPath) holds a \(kind) value; a document holds only strings, numbers, "
        + "booleans, arrays, and dictionaries"
    }
  }
}

/// Reads and writes stored documents: XML property lists in UTF-8 with sorted keys, the form
/// `PropertyListSerialization` writes.
public enum DocumentCoder {
  /// The document in `data` as a Foundation tree: integers and reals keep their type.
  ///
  /// Throws ``DocumentCoderError`` for any other form and for a `date` or `data` value; `file`
  /// names the file in the error.
  public static func read(_ data: Data, file: String) throws -> Any {
    var format = PropertyListSerialization.PropertyListFormat.xml
    let tree: Any
    do {
      tree = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
    } catch {
      let json = (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) != nil
      throw DocumentCoderError(file: file, reason: json ? .json : .notXML)
    }
    guard format == .xml else {
      throw DocumentCoderError(file: file, reason: format == .binary ? .binary : .notXML)
    }
    try check(tree, keyPath: "", file: file)
    return tree
  }

  /// The document in `data` as a `T`.
  public static func decode<T: Decodable>(_ type: T.Type, from data: Data, file: String) throws
    -> T
  {
    _ = try read(data, file: file)
    return try PropertyListDecoder().decode(type, from: data)
  }

  /// `value` as a canonical document.
  public static func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .xml
    return try encoder.encode(value)
  }

  /// A Foundation tree as a canonical document.
  public static func write(_ tree: Any) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: tree, format: .xml, options: 0)
  }

  private static func check(_ value: Any, keyPath: String, file: String) throws {
    switch value {
    case let dictionary as [String: Any]:
      for (key, child) in dictionary {
        try check(child, keyPath: keyPath.isEmpty ? key : "\(keyPath).\(key)", file: file)
      }
    case let list as [Any]:
      for (index, child) in list.enumerated() {
        try check(child, keyPath: "\(keyPath)[\(index)]", file: file)
      }
    case is Date:
      throw DocumentCoderError(file: file, reason: .unsupportedValue(keyPath: keyPath, kind: "date"))
    case is Data:
      throw DocumentCoderError(file: file, reason: .unsupportedValue(keyPath: keyPath, kind: "data"))
    default:
      break
    }
  }
}
