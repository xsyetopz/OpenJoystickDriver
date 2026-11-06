import Foundation

/// A key for a JSON object whose field names are not known in advance.
private struct RemappingJSONKey: CodingKey {
  /// The field name.
  let stringValue: String
  /// Always `nil`, because the key names only object fields and never an array index.
  let intValue: Int? = nil

  /// Creates a key from a field name.
  init?(stringValue: String) { self.stringValue = stringValue }
  /// Fails for every integer, because the key names only object fields.
  init?(intValue: Int) { return nil }
}

extension Decoder {
  /// Throws when the current JSON object has a key that `Keys` does not declare.
  public func rejectUnknownKeys<Keys: CodingKey & CaseIterable>(_ keys: Keys.Type) throws {
    let container = try self.container(keyedBy: RemappingJSONKey.self)
    let allowed = Set(Keys.allCases.map(\.stringValue))
    let unknown = Set(container.allKeys.map(\.stringValue)).subtracting(allowed).sorted()
    guard unknown.isEmpty else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: codingPath,
          debugDescription: "unknown field(s): \(unknown.joined(separator: ", "))"
        )
      )
    }
  }
}

extension KeyedDecodingContainer {
  /// Throws when the object has a declared key that the decoded variant does not use.
  ///
  /// Discriminated enums declare the union of every variant's keys, so `rejectUnknownKeys`
  /// alone would accept a key that belongs to another variant.
  public func rejectKeys(otherThan allowed: [Key]) throws {
    let allowedNames = Set(allowed.map(\.stringValue))
    let extra = allKeys.map(\.stringValue).filter { !allowedNames.contains($0) }.sorted()
    guard extra.isEmpty else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: codingPath,
          debugDescription: "field(s) not valid for this type: \(extra.joined(separator: ", "))"
        )
      )
    }
  }
}
