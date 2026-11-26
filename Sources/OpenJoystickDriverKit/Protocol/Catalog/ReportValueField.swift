/// A numeric input field: the bits, their byte order and signedness, and the raw range that
/// scales to the full travel.
public struct ReportValueField: Hashable, Sendable {
  /// The index of the first bit of the field.
  public let bitOffset: Int
  /// The number of bits of the field, 1 to 32.
  public let bitSize: Int
  /// The byte order of the field.
  public let byteOrder: ReportByteOrder
  /// Whether the raw value is two's complement over `bitSize`.
  public let isSigned: Bool
  /// The raw value that reads as the lowest position.
  public let minimum: Int
  /// The raw value that reads as the highest position.
  public let maximum: Int

  /// The representable range of a raw value of this size and signedness.
  var fullRange: ClosedRange<Int> { Self.fullRange(bitSize: bitSize, isSigned: isSigned) }

  /// The representable range of a raw value of `bitSize` bits and the given signedness.
  static func fullRange(bitSize: Int, isSigned: Bool) -> ClosedRange<Int> {
    isSigned
      ? -(1 << (bitSize - 1))...((1 << (bitSize - 1)) - 1)
      : 0...((1 << bitSize) - 1)
  }

  /// Whether the byte order, offset and size agree: a big-endian field starts on a byte boundary
  /// and holds 16, 24 or 32 bits.
  var hasValidByteOrder: Bool {
    byteOrder == .littleEndian || (bitOffset.isMultiple(of: 8) && [16, 24, 32].contains(bitSize))
  }

  /// The raw value in `bytes`, sign-extended when the field is signed.
  func raw(in bytes: [UInt8]) -> Int {
    var value: UInt64
    switch byteOrder {
    case .littleEndian: value = ReportBitField.bits(in: bytes, offset: bitOffset, size: bitSize)
    case .bigEndian:
      value = 0
      for index in 0..<(bitSize / 8) { value = value << 8 | UInt64(bytes[bitOffset / 8 + index]) }
    }
    let number = Int(value)
    guard isSigned, number >= 1 << (bitSize - 1) else { return number }
    return number - (1 << bitSize)
  }
}
