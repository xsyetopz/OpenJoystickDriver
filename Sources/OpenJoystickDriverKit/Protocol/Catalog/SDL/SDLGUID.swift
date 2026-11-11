import Foundation

/// An SDL joystick GUID: 16 bytes, written as 32 lowercase hexadecimal digits.
///
/// The layout is the bus (2 bytes, little endian), the CRC16 of the name (2), the vendor (2), 2
/// zero bytes, the product (2), 2 zero bytes, the version (2) and 2 zero bytes.
struct SDLGUID: Hashable, Sendable, CustomStringConvertible {
  /// The bus of a USB device in SDL's `SDL_HARDWARE_BUS_USB`.
  private static let usbBus: UInt16 = 3

  /// The 16 bytes.
  let bytes: [UInt8]

  /// The GUID IOKit-reported identity gives: bus USB, then the CRC16 of the name, vendor,
  /// product and version.
  ///
  /// The name is `manufacturer + " " + product`, or the product alone when there is no
  /// manufacturer.
  init(vendorID: UInt16, productID: UInt16, version: UInt16, manufacturer: String?, product: String)
  {
    let name = manufacturer.flatMap { $0.isEmpty ? nil : $0 + " " + product } ?? product
    let crc = Self.crc16(Array(name.utf8))
    var packed: [UInt8] = []
    for word in [Self.usbBus, crc, vendorID, 0, productID, 0, version, 0] {
      packed += [UInt8(word & 0xFF), UInt8(word >> 8)]
    }
    self.bytes = packed
  }

  /// The GUID written as `text`, or nil unless it is 32 hexadecimal digits.
  init?(_ text: String) {
    let digits = Array(text)
    guard digits.count == 32 else { return nil }
    var packed: [UInt8] = []
    for pair in stride(from: 0, to: 32, by: 2) {
      guard let byte = UInt8(String(digits[pair..<pair + 2]), radix: 16) else { return nil }
      packed.append(byte)
    }
    self.bytes = packed
  }

  /// The GUID made of `bytes`.
  private init(bytes: [UInt8]) { self.bytes = bytes }

  /// This GUID with the CRC bytes zeroed.
  var withoutNameCRC: Self { zeroing(2..<4) }

  /// This GUID with the version bytes zeroed.
  var withoutVersion: Self { zeroing(12..<14) }

  /// The 32 lowercase hexadecimal digits.
  var description: String { bytes.map { unsafe String(format: "%02x", $0) }.joined() }

  /// This GUID with the bytes in `range` zeroed.
  private func zeroing(_ range: Range<Int>) -> Self {
    var bytes = bytes
    for index in range { bytes[index] = 0 }
    return Self(bytes: bytes)
  }

  /// CRC-16/ARC of `bytes`, as SDL's `SDL_crc16` computes it from 0.
  static func crc16(_ bytes: [UInt8]) -> UInt16 {
    var crc: UInt16 = 0
    for byte in bytes {
      crc ^= UInt16(byte)
      for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xA001 : crc >> 1 }
    }
    return crc
  }
}
