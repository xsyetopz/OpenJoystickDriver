import Foundation

extension OrderedJSON: Encodable {
  /// Hands the value to an ``OrderedJSONEncoder``, which writes it as it is: members in their order
  /// and a number as its text.
  ///
  /// Any other `Encoder` throws, because it would sort the members or re-encode a number.
  public func encode(to encoder: any Encoder) throws {
    guard let writer = encoder as? OrderedJSONEncoder.Writer else {
      throw EncodingError.invalidValue(
        self,
        .init(
          codingPath: encoder.codingPath,
          debugDescription: "OrderedJSON is encoded by OrderedJSONEncoder only"
        )
      )
    }
    writer.node.value = .leaf(self)
  }
}

/// An `Encoder` that builds an ``OrderedJSON``.
///
/// The members of a Swift value are sorted by name, as `JSONEncoder` sorts them with `.sortedKeys`,
/// and an embedded ``OrderedJSON`` is kept as it is, so a record keeps its member order and the
/// text of its numbers.
public struct OrderedJSONEncoder {
  /// Creates an encoder.
  public init() {}

  /// The JSON value `value` encodes to.
  ///
  /// A `Double` or `Float` that is not finite throws, as JSON cannot hold it. A value that writes
  /// nothing encodes to an empty object.
  public func encode(_ value: some Encodable) throws -> OrderedJSON {
    try Self.node(value, at: []).resolved()
  }

  /// The value being built at one place of the document.
  final class Node {
    /// What a ``Node`` holds so far.
    enum Value {
      /// Nothing is encoded yet; the node resolves to an empty object.
      case unset
      /// Members by name; they resolve sorted by name.
      case object([String: Node])
      /// Elements in order.
      case array([Node])
      /// A finished value that is kept as it is.
      case leaf(OrderedJSON)
    }

    /// The content of the node.
    var value = Value.unset

    /// The ``OrderedJSON`` of the node and the nodes below it.
    func resolved() -> OrderedJSON {
      switch value {
      case .unset: return .object([])
      case .leaf(let json): return json
      case .array(let items): return .array(items.map { $0.resolved() })
      case .object(let members):
        return .object(
          members.sorted { $0.key < $1.key }.map { .init(key: $0.key, value: $0.value.resolved()) }
        )
      }
    }
  }

  /// A coding key that is a member name or an array index.
  struct Key: CodingKey {
    /// The member name.
    let stringValue: String
    /// The array index; nil for a member name.
    let intValue: Int?
    /// Creates a key for a member name.
    init(stringValue: String) {
      self.stringValue = stringValue
      intValue = nil
    }
    /// Creates a key for an array index, named by the number text.
    init(intValue: Int) {
      stringValue = String(intValue)
      self.intValue = intValue
    }
  }

  /// The encoder that writes into one node.
  final class Writer: Encoder {
    /// The node the container writes into.
    let node: Node
    /// The path from the document root to the node.
    let codingPath: [any CodingKey]
    /// The user info, always empty.
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    /// Creates a writer for a node at a coding path.
    init(node: Node, codingPath: [any CodingKey]) {
      self.node = node
      self.codingPath = codingPath
    }

    /// Returns a keyed container over the node; a node with nothing encoded becomes an empty
    /// object.
    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
      if case .unset = node.value { node.value = .object([:]) }
      guard case .object = node.value else {
        preconditionFailure("a keyed container over a value that is not an object")
      }
      return KeyedEncodingContainer(KeyedWriter<Key>(node: node, codingPath: codingPath))
    }

    /// Returns an unkeyed container over the node; a node with nothing encoded becomes an empty
    /// array.
    func unkeyedContainer() -> any UnkeyedEncodingContainer {
      if case .unset = node.value { node.value = .array([]) }
      guard case .array = node.value else {
        preconditionFailure("an unkeyed container over a value that is not an array")
      }
      return UnkeyedWriter(node: node, codingPath: codingPath)
    }

    /// Returns a container that sets the node to one value.
    func singleValueContainer() -> any SingleValueEncodingContainer {
      SingleWriter(node: node, codingPath: codingPath)
    }
  }

  /// The JSON number for `integer`.
  private static func number(_ integer: some BinaryInteger) -> OrderedJSON {
    .number(String(integer))
  }

  /// The JSON number for `value`, as `JSONEncoder` writes it: the shortest text that reads back
  /// as `value`, without a trailing `.0`.
  private static func number<Value: BinaryFloatingPoint>(
    _ value: Value,
    at codingPath: [any CodingKey]
  ) throws -> OrderedJSON where Value: CustomStringConvertible {
    guard value.isFinite else {
      throw EncodingError.invalidValue(
        value,
        .init(codingPath: codingPath, debugDescription: "JSON cannot hold \(value)")
      )
    }
    let text = value.description
    return .number(text.hasSuffix(".0") ? String(text.dropLast(2)) : text)
  }

  /// Encodes `value` into a node.
  private static func node(
    _ value: some Encodable,
    at codingPath: [any CodingKey]
  ) throws -> Node {
    let node = Node()
    if let json = try foundationValue(value, at: codingPath) {
      node.value = .leaf(json)
    } else {
      try value.encode(to: Writer(node: node, codingPath: codingPath))
    }
    return node
  }

  /// The JSON that `JSONEncoder` writes for a `Data`, a `Decimal` or a `URL`, whose own
  /// `encode(to:)` writes another shape: `Data` as base64 text, `Decimal` as a number and `URL` as
  /// its text.
  ///
  /// Any other value is nil.
  private static func foundationValue(
    _ value: some Encodable,
    at codingPath: [any CodingKey]
  ) throws -> OrderedJSON? {
    switch value {
    case let data as Data: return .string(data.base64EncodedString())
    case let url as URL: return .string(url.absoluteString)
    case let decimal as Decimal:
      guard decimal.isFinite else {
        throw EncodingError.invalidValue(
          decimal,
          .init(codingPath: codingPath, debugDescription: "JSON cannot hold \(decimal)")
        )
      }
      return .number(decimal.description)
    default: return nil
    }
  }

  /// A node that holds `json` as it is.
  private static func leaf(_ json: OrderedJSON) -> Node {
    let node = Node()
    node.value = .leaf(json)
    return node
  }

  /// The keyed container that sets the members of an object node.
  private struct KeyedWriter<Key: CodingKey>: KeyedEncodingContainerProtocol {
    /// The node the container writes into.
    let node: Node
    /// The path from the document root to the node.
    let codingPath: [any CodingKey]

    /// Sets the member `key` to a child node.
    private func set(_ key: Key, _ member: Node) {
      guard case .object(var members) = node.value else { return }
      members[key.stringValue] = member
      node.value = .object(members)
    }

    /// Sets the member `key` to a finished value.
    private func set(_ key: Key, _ json: OrderedJSON) { set(key, OrderedJSONEncoder.leaf(json)) }

    /// Encodes `null` under `key`.
    func encodeNil(forKey key: Key) throws { set(key, .null) }
    /// Encodes a `Bool` under `key`.
    func encode(_ value: Bool, forKey key: Key) throws { set(key, .bool(value)) }
    /// Encodes a `String` under `key`.
    func encode(_ value: String, forKey key: Key) throws { set(key, .string(value)) }
    /// Encodes a `Double` under `key`.
    ///
    /// Throws when it is not finite, because JSON cannot hold it.
    func encode(_ value: Double, forKey key: Key) throws {
      set(key, try OrderedJSONEncoder.number(value, at: codingPath + [key]))
    }
    /// Encodes a `Float` under `key`.
    ///
    /// Throws when it is not finite, because JSON cannot hold it.
    func encode(_ value: Float, forKey key: Key) throws {
      set(key, try OrderedJSONEncoder.number(value, at: codingPath + [key]))
    }
    /// Encodes a `Int` under `key`.
    func encode(_ value: Int, forKey key: Key) throws { set(key, OrderedJSONEncoder.number(value)) }
    /// Encodes a `Int8` under `key`.
    func encode(_ value: Int8, forKey key: Key) throws {
      set(key, OrderedJSONEncoder.number(value))
    }
    /// Encodes a `Int16` under `key`.
    func encode(_ value: Int16, forKey key: Key) throws {
      set(key, OrderedJSONEncoder.number(value))
    }
    /// Encodes a `Int32` under `key`.
    func encode(_ value: Int32, forKey key: Key) throws {
      set(key, OrderedJSONEncoder.number(value))
    }
    /// Encodes a `Int64` under `key`.
    func encode(_ value: Int64, forKey key: Key) throws {
      set(key, OrderedJSONEncoder.number(value))
    }
    /// Encodes a `UInt` under `key`.
    func encode(_ value: UInt, forKey key: Key) throws {
      set(key, OrderedJSONEncoder.number(value))
    }
    /// Encodes a `UInt8` under `key`.
    func encode(_ value: UInt8, forKey key: Key) throws {
      set(key, OrderedJSONEncoder.number(value))
    }
    /// Encodes a `UInt16` under `key`.
    func encode(_ value: UInt16, forKey key: Key) throws {
      set(key, OrderedJSONEncoder.number(value))
    }
    /// Encodes a `UInt32` under `key`.
    func encode(_ value: UInt32, forKey key: Key) throws {
      set(key, OrderedJSONEncoder.number(value))
    }
    /// Encodes a `UInt64` under `key`.
    func encode(_ value: UInt64, forKey key: Key) throws {
      set(key, OrderedJSONEncoder.number(value))
    }
    /// Encodes any `Encodable` value under `key`, as a nested node.
    func encode<Value: Encodable>(_ value: Value, forKey key: Key) throws {
      set(key, try OrderedJSONEncoder.node(value, at: codingPath + [key]))
    }

    /// Returns a keyed container for a new object under `key`.
    func nestedContainer<NestedKey: CodingKey>(
      keyedBy keyType: NestedKey.Type,
      forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> {
      let child = Node()
      set(key, child)
      return Writer(node: child, codingPath: codingPath + [key]).container(keyedBy: keyType)
    }

    /// Returns an unkeyed container for a new array under `key`.
    func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
      let child = Node()
      set(key, child)
      return Writer(node: child, codingPath: codingPath + [key]).unkeyedContainer()
    }

    /// Returns an encoder for the member `super`.
    func superEncoder() -> any Encoder { superEncoder(named: "super") }
    /// Returns an encoder for the member `key`.
    func superEncoder(forKey key: Key) -> any Encoder { superEncoder(named: key.stringValue) }

    /// Returns an encoder for a new member called `name`.
    private func superEncoder(named name: String) -> any Encoder {
      let child = Node()
      guard case .object(var members) = node.value else { preconditionFailure("not an object") }
      members[name] = child
      node.value = .object(members)
      return Writer(
        node: child,
        codingPath: codingPath + [OrderedJSONEncoder.Key(stringValue: name)]
      )
    }
  }

  /// The unkeyed container that appends the elements of an array node.
  private struct UnkeyedWriter: UnkeyedEncodingContainer {
    /// The node the container writes into.
    let node: Node
    /// The path from the document root to the node.
    let codingPath: [any CodingKey]

    /// The number of elements encoded so far.
    var count: Int {
      guard case .array(let items) = node.value else { return 0 }
      return items.count
    }

    /// The coding path of the next element.
    private var nextPath: [any CodingKey] { codingPath + [Key(intValue: count)] }

    /// Appends a child node as an element.
    private func append(_ item: Node) {
      guard case .array(var items) = node.value else { return }
      items.append(item)
      node.value = .array(items)
    }

    /// Appends a finished value as an element.
    private func append(_ json: OrderedJSON) { append(OrderedJSONEncoder.leaf(json)) }

    /// Appends `null`.
    mutating func encodeNil() throws { append(.null) }
    /// Appends a `Bool`.
    mutating func encode(_ value: Bool) throws { append(.bool(value)) }
    /// Appends a `String`.
    mutating func encode(_ value: String) throws { append(.string(value)) }
    /// Appends a `Double`.
    ///
    /// Throws when it is not finite, because JSON cannot hold it.
    mutating func encode(_ value: Double) throws {
      append(try OrderedJSONEncoder.number(value, at: nextPath))
    }
    /// Appends a `Float`.
    ///
    /// Throws when it is not finite, because JSON cannot hold it.
    mutating func encode(_ value: Float) throws {
      append(try OrderedJSONEncoder.number(value, at: nextPath))
    }
    /// Appends a `Int`.
    mutating func encode(_ value: Int) throws { append(OrderedJSONEncoder.number(value)) }
    /// Appends a `Int8`.
    mutating func encode(_ value: Int8) throws { append(OrderedJSONEncoder.number(value)) }
    /// Appends a `Int16`.
    mutating func encode(_ value: Int16) throws { append(OrderedJSONEncoder.number(value)) }
    /// Appends a `Int32`.
    mutating func encode(_ value: Int32) throws { append(OrderedJSONEncoder.number(value)) }
    /// Appends a `Int64`.
    mutating func encode(_ value: Int64) throws { append(OrderedJSONEncoder.number(value)) }
    /// Appends a `UInt`.
    mutating func encode(_ value: UInt) throws { append(OrderedJSONEncoder.number(value)) }
    /// Appends a `UInt8`.
    mutating func encode(_ value: UInt8) throws { append(OrderedJSONEncoder.number(value)) }
    /// Appends a `UInt16`.
    mutating func encode(_ value: UInt16) throws { append(OrderedJSONEncoder.number(value)) }
    /// Appends a `UInt32`.
    mutating func encode(_ value: UInt32) throws { append(OrderedJSONEncoder.number(value)) }
    /// Appends a `UInt64`.
    mutating func encode(_ value: UInt64) throws { append(OrderedJSONEncoder.number(value)) }
    /// Appends any `Encodable` value as a nested node.
    mutating func encode<Value: Encodable>(_ value: Value) throws {
      append(try OrderedJSONEncoder.node(value, at: nextPath))
    }

    /// Appends a new object and returns a keyed container for it.
    mutating func nestedContainer<NestedKey: CodingKey>(
      keyedBy keyType: NestedKey.Type
    ) -> KeyedEncodingContainer<NestedKey> {
      let path = nextPath
      let child = Node()
      append(child)
      return Writer(node: child, codingPath: path).container(keyedBy: keyType)
    }

    /// Appends a new array and returns an unkeyed container for it.
    mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
      let path = nextPath
      let child = Node()
      append(child)
      return Writer(node: child, codingPath: path).unkeyedContainer()
    }

    /// Appends a new element and returns an encoder for it.
    mutating func superEncoder() -> any Encoder {
      let path = nextPath
      let child = Node()
      append(child)
      return Writer(node: child, codingPath: path)
    }
  }

  /// The single-value container that sets the value of a node.
  private struct SingleWriter: SingleValueEncodingContainer {
    /// The node the container writes into.
    let node: Node
    /// The path from the document root to the node.
    let codingPath: [any CodingKey]

    /// Sets the node to a finished value.
    private func set(_ json: OrderedJSON) { node.value = .leaf(json) }

    /// Sets the node to `null`.
    func encodeNil() throws { set(.null) }
    /// Sets the node to a `Bool`.
    func encode(_ value: Bool) throws { set(.bool(value)) }
    /// Sets the node to a `String`.
    func encode(_ value: String) throws { set(.string(value)) }
    /// Sets the node to a `Double`.
    ///
    /// Throws when it is not finite, because JSON cannot hold it.
    func encode(_ value: Double) throws {
      set(try OrderedJSONEncoder.number(value, at: codingPath))
    }
    /// Sets the node to a `Float`.
    ///
    /// Throws when it is not finite, because JSON cannot hold it.
    func encode(_ value: Float) throws {
      set(try OrderedJSONEncoder.number(value, at: codingPath))
    }
    /// Sets the node to a `Int`.
    func encode(_ value: Int) throws { set(OrderedJSONEncoder.number(value)) }
    /// Sets the node to a `Int8`.
    func encode(_ value: Int8) throws { set(OrderedJSONEncoder.number(value)) }
    /// Sets the node to a `Int16`.
    func encode(_ value: Int16) throws { set(OrderedJSONEncoder.number(value)) }
    /// Sets the node to a `Int32`.
    func encode(_ value: Int32) throws { set(OrderedJSONEncoder.number(value)) }
    /// Sets the node to a `Int64`.
    func encode(_ value: Int64) throws { set(OrderedJSONEncoder.number(value)) }
    /// Sets the node to a `UInt`.
    func encode(_ value: UInt) throws { set(OrderedJSONEncoder.number(value)) }
    /// Sets the node to a `UInt8`.
    func encode(_ value: UInt8) throws { set(OrderedJSONEncoder.number(value)) }
    /// Sets the node to a `UInt16`.
    func encode(_ value: UInt16) throws { set(OrderedJSONEncoder.number(value)) }
    /// Sets the node to a `UInt32`.
    func encode(_ value: UInt32) throws { set(OrderedJSONEncoder.number(value)) }
    /// Sets the node to a `UInt64`.
    func encode(_ value: UInt64) throws { set(OrderedJSONEncoder.number(value)) }
    /// Sets the node to the node of any `Encodable` value.
    func encode<Value: Encodable>(_ value: Value) throws {
      node.value = try OrderedJSONEncoder.node(value, at: codingPath).value
    }
  }
}
