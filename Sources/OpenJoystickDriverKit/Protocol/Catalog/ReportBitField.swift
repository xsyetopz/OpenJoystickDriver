/// The byte order of a multi-byte input field.
public enum ReportByteOrder: String, Sendable {
  /// The first byte holds the least significant bits, as HID packs a field.
  case littleEndian = "LittleEndian"
  /// The first byte holds the most significant bits; only a byte-aligned field of 16, 24 or 32
  /// bits has this order.
  case bigEndian = "BigEndian"
}

/// The `bitSize` bits from `bitOffset` of an input report, counted from the least significant bit
/// of byte 0.
public struct ReportBitField: Hashable, Sendable {
  /// The widest field, in bits.
  static let maximumBitSize = 32

  /// The index of the first bit of the field.
  public let bitOffset: Int
  /// The number of bits of the field, 1 to 32.
  public let bitSize: Int

  /// Whether any bit of the field is set in `bytes`.
  func isSet(in bytes: [UInt8]) -> Bool {
    Self.bits(in: bytes, offset: bitOffset, size: bitSize) != 0
  }

  /// The field as an unsigned little-endian number.
  func value(in bytes: [UInt8]) -> Int {
    Int(Self.bits(in: bytes, offset: bitOffset, size: bitSize))
  }

  /// The `size` bits from `offset` as an unsigned little-endian number: bit `offset` of the report
  /// is bit 0 of the result.
  static func bits(in bytes: [UInt8], offset: Int, size: Int) -> UInt64 {
    var value: UInt64 = 0
    for index in 0..<size {
      let bit = offset + index
      if bytes[bit >> 3] >> UInt8(bit & 7) & 1 != 0 { value |= 1 << UInt64(index) }
    }
    return value
  }
}
