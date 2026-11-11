/// CRC-32 (reflected polynomial `0xEDB88320`) that Sony DualShock 4 and DualSense Bluetooth
/// reports carry in their last four bytes, little-endian.
///
/// The checksum covers a one-byte seed (the HID transaction header: `0xA1` input, `0xA2`
/// output, `0xA3` feature) followed by every report byte before the trailer.
enum SonyBluetoothCRC32 {
  /// The length of the CRC trailer in bytes.
  static let trailerLength = 4

  /// The checksum of `seed` followed by `bytes`.
  static func checksum(seed: UInt8, bytes: some Sequence<UInt8>) -> UInt32 {
    var crc = update(0xFFFF_FFFF, byte: seed)
    for byte in bytes { crc = update(crc, byte: byte) }
    return ~crc
  }

  /// Returns whether the report's trailing four bytes match the checksum of the bytes before them.
  static func isValid(seed: UInt8, report: [UInt8]) -> Bool {
    guard report.count >= trailerLength else { return false }
    let stored = report.suffix(trailerLength).enumerated().reduce(UInt32(0)) { value, element in
      value | (UInt32(element.element) << UInt32(element.offset * 8))
    }
    return checksum(seed: seed, bytes: report.dropLast(trailerLength)) == stored
  }

  /// Overwrites the report's trailing four bytes with the checksum of the bytes before them.
  static func writeTrailer(seed: UInt8, report: inout [UInt8]) {
    precondition(report.count >= trailerLength, "Sony Bluetooth report has no CRC trailer")
    let crc = checksum(seed: seed, bytes: report.dropLast(trailerLength))
    let offset = report.count - trailerLength
    for index in 0..<trailerLength {
      report[offset + index] = UInt8(truncatingIfNeeded: crc >> UInt32(index * 8))
    }
  }

  /// Folds `byte` into the running checksum `current`.
  private static func update(_ current: UInt32, byte: UInt8) -> UInt32 {
    var crc = current ^ UInt32(byte)
    for _ in 0..<8 { if crc & 1 == 1 { crc = (crc >> 1) ^ 0xEDB8_8320 } else { crc >>= 1 } }
    return crc
  }
}
