package import Foundation

/// Writes a test document as a canonical XML property list, the form every stored document has.
///
/// A fixture states its tree as a JSON literal because that reads well in a test; this type
/// parses the literal and writes the tree with `PropertyListSerialization`, so the file holds no
/// JSON.
package enum PropertyListFixture {
  /// The XML property list for the tree `literal` states.
  package static func data(json literal: String) throws -> Data {
    try data(json: Data(literal.utf8))
  }

  /// The XML property list for the tree `literal` states.
  package static func data(json literal: Data) throws -> Data {
    let tree = try JSONSerialization.jsonObject(with: literal, options: .fragmentsAllowed)
    return try data(tree: tree)
  }

  // A literal that is no JSON stays as its own bytes, so the reader under test refuses it.
  package static func bytes(json literal: String) -> Data {
    (try? data(json: literal)) ?? Data(literal.utf8)
  }

  // A tree that no property list holds gives empty data.
  package static func bytes(tree: Any) -> Data { (try? data(tree: tree)) ?? Data() }

  /// The XML property list for a Foundation tree.
  package static func data(tree: Any) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: tree, format: .xml, options: 0)
  }

  /// The tree that the property list `data` holds.
  package static func tree(_ data: Data) throws -> Any {
    try unsafe PropertyListSerialization.propertyList(from: data, options: 0, format: nil)
  }

  /// The tree that the property list file at `url` holds, as a dictionary.
  package static func dictionary(at url: URL) throws -> [String: Any] {
    guard let tree = try tree(Data(contentsOf: url)) as? [String: Any] else {
      throw CocoaError(.propertyListReadCorrupt)
    }
    return tree
  }

  /// Writes the tree `literal` states to `url` as an XML property list.
  package static func write(json literal: String, to url: URL) throws {
    try data(json: literal).write(to: url)
  }
}
