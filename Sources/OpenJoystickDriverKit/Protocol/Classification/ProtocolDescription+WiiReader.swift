import Foundation

/// Strict reads of one JSON object for the Wii Remote field: every failure names the key.
struct WiiReader {
  /// The object being read.
  let container: KeyedDecodingContainer<DocumentKey>

  /// The keys the object sets.
  var keys: Set<String> { Set(container.allKeys.map(\.stringValue)) }

  /// Reads `container`, rejecting any key outside `allowed`.
  init(_ container: KeyedDecodingContainer<DocumentKey>, allowed: Set<String>) throws {
    try container.rejectUnknown(allowed: allowed)
    self.container = container
  }

  /// A decoding error at `key`.
  func fail(_ key: String, _ text: String) -> DecodingError {
    .dataCorrupted(
      .init(codingPath: container.codingPath + [DocumentKey(key)], debugDescription: text)
    )
  }

  /// The integer at `key`, inside `range`.
  func number(_ key: String, _ range: ClosedRange<Int>) throws -> Int {
    let value = try container.decode(Int.self, for: key)
    guard range.contains(value) else {
      throw fail(key, "\(key) must be in \(range.lowerBound)...\(range.upperBound)")
    }
    return value
  }

  /// The string at `key`.
  func string(_ key: String) throws -> String { try container.decode(String.self, for: key) }

  /// The string array at `key`.
  func strings(_ key: String) throws -> [String] { try container.decode([String].self, for: key) }

  /// The hex bytes at `key`, `count` bytes long.
  func bytes(_ key: String, _ count: ClosedRange<Int>) throws -> [UInt8] {
    guard let bytes = HexBytes.parse(try string(key)), count.contains(bytes.count) else {
      throw fail(key, "\(key) is \(count.lowerBound)...\(count.upperBound) \(HexBytes.message)")
    }
    return bytes
  }

  /// The 24-bit register address of the `address` key, six uppercase hex digits.
  func address() throws -> UInt32 {
    let text = try string("address")
    guard text.count == 6, text.allSatisfy({ "0123456789ABCDEF".contains($0) }),
      let value = UInt32(text, radix: 16)
    else { throw fail("address", "address is six uppercase hex digits") }
    return value
  }

  /// The `byte` and `mask` of a bit field whose byte lies in `bytes`.
  func bitField(bytes: ClosedRange<Int>) throws -> ProtocolDescription.WiiRemote.BitField {
    .init(byte: try number("byte", bytes), mask: UInt8(try number("mask", 1...255)))
  }

  /// The control named by the `control` key.
  func control() throws -> Control {
    let name = try string("control")
    guard let control = Control(rawValue: name) else {
      throw fail("control", "\(name) is not a control")
    }
    return control
  }

  /// The one to three contiguous runs of bits at `key`, most significant first.
  func field(_ key: String) throws -> ProtocolDescription.WiiRemote.ExtensionField {
    let parts = try list(key, 1...3, allowed: ["byte", "mask"]) { try $0.bitField(bytes: 0...5) }
    for part in parts {
      let run = part.mask >> part.mask.trailingZeroBitCount
      guard run & (run &+ 1) == 0 else { throw fail(key, "a mask is one run of set bits") }
    }
    return .init(parts: parts)
  }

  /// The nested object at `key`, limited to the `allowed` keys.
  func object(_ key: String, allowed: Set<String>) throws -> Self {
    try Self(
      try container.nestedContainer(keyedBy: DocumentKey.self, forKey: DocumentKey(key)),
      allowed: allowed
    )
  }

  /// The array at `key` of `count` entries, each read with `read`.
  func list<Value>(
    _ key: String,
    _ count: ClosedRange<Int>,
    allowed: Set<String>,
    _ read: (Self) throws -> Value
  ) throws -> [Value] {
    var unkeyed = try container.nestedUnkeyedContainer(forKey: DocumentKey(key))
    var values: [Value] = []
    while !unkeyed.isAtEnd {
      let item = try Self(
        try unkeyed.nestedContainer(keyedBy: DocumentKey.self),
        allowed: allowed
      )
      values.append(try read(item))
    }
    guard count.contains(values.count) else {
      throw fail(key, "\(key) names \(count.lowerBound)...\(count.upperBound) entries")
    }
    return values
  }
}
