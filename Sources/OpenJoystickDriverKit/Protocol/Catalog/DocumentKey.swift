import Foundation

/// A coding key for any field name, so the strict decoders can name and reject fields.
struct DocumentKey: CodingKey, Hashable {
  /// The field name.
  let stringValue: String
  /// Always `nil`, because the keys are strings.
  let intValue: Int? = nil

  /// Creates a key from a field name.
  init(_ value: String) { stringValue = value }
  /// Creates a key from any string.
  init?(stringValue: String) { self.init(stringValue) }
  /// Creates a key from the decimal text of an integer.
  init?(intValue: Int) { self.init(String(intValue)) }
}

extension KeyedDecodingContainer where Key == DocumentKey {
  /// Decodes the value under `key`.
  func decode<T: Decodable>(_ type: T.Type, for key: String) throws -> T {
    try decode(type, forKey: DocumentKey(key))
  }

  /// Decodes the value under `key`, or nil when the key is absent; an explicit null fails.
  func decodeOptional<T: Decodable>(_ type: T.Type, for key: String) throws -> T? {
    let codingKey = DocumentKey(key)
    guard contains(codingKey) else { return nil }
    guard try !decodeNil(forKey: codingKey) else {
      throw DecodingError.valueNotFound(
        type,
        .init(codingPath: codingPath + [codingKey], debugDescription: "null is not permitted")
      )
    }
    return try decode(type, forKey: codingKey)
  }

  /// Decodes a nonempty list of unique current identifiers; unknown values fail.
  func decodeUniqueList<Value: RawRepresentable & Hashable>(
    _: Value.Type,
    for key: String
  ) throws -> [Value]? where Value.RawValue == String {
    guard let names = try decodeOptional([String].self, for: key) else { return nil }
    let values = names.compactMap(Value.init(rawValue:))
    guard !values.isEmpty, values.count == names.count, Set(values).count == values.count else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: codingPath + [DocumentKey(key)],
          debugDescription: "\(key) must contain unique, current, nonempty values"
        )
      )
    }
    return values
  }

  /// Decodes a nonempty list of unique ids of named packets that the description of `family`
  /// defines.
  ///
  /// Any other id fails.
  func decodeNamedPacketList(of family: PhysicalProtocolID, for key: String) throws -> [String]? {
    guard let names = try decodeOptional([String].self, for: key) else { return nil }
    let plan = ProtocolDescription.bundled[family]?.namedPackets
    guard !names.isEmpty, Set(names).count == names.count,
      names.allSatisfy({ plan?.packet(named: $0) != nil })
    else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: codingPath + [DocumentKey(key)],
          debugDescription: "\(key) must contain unique, nonempty ids of the family's named packets"
        )
      )
    }
    return names
  }

  /// Fails when the container holds a key outside `allowed`.
  /// - Throws: `DecodingError.dataCorrupted` naming the unknown fields.
  func rejectUnknown(allowed: Set<String>) throws {
    let unknown = Set(allKeys.map(\.stringValue)).subtracting(allowed).sorted()
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
