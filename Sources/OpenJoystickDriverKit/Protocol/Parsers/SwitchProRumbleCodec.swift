import Foundation

/// Linux-compatible Switch HD-rumble encoding at the default 160/320 Hz frequencies.
enum SwitchProRumbleCodec {
  /// Rounded amplitude thresholds from Linux `hid-nintendo.c`.
  private static let amplitudeThresholds: [UInt16] = [
    0, 10, 12, 14, 17, 20, 24, 28, 33, 40, 47, 56, 67, 80, 95, 112, 117, 123, 128, 134, 140, 146,
    152, 159, 166, 173, 181, 189, 198, 206, 215, 225, 230, 235, 240, 245, 251, 256, 262, 268, 273,
    279, 286, 292, 298, 305, 311, 318, 325, 332, 340, 347, 355, 362, 370, 378, 387, 395, 404, 413,
    422, 431, 440, 450, 460, 470, 480, 491, 501, 512, 524, 535, 547, 559, 571, 584, 596, 609, 623,
    636, 650, 665, 679, 694, 709, 725, 741, 757, 773, 790, 808, 825, 843, 862, 881, 900, 920, 940,
    960, 981, 1003,
  ]

  static func encode(intensity: UInt8) -> [UInt8] {
    let amplitude = UInt16(UInt32(intensity) * 1003 / 255)
    let index = amplitudeThresholds.firstIndex { amplitude <= $0 } ?? 100
    let amplitudeHigh = UInt8(index * 2)
    let amplitudeLowHigh: UInt8 = index.isMultiple(of: 2) ? 0 : 0x80
    let amplitudeLow = UInt8(0x40 + (index + 1) / 2)

    // Default high frequency 320 Hz encodes as 0x0001; low frequency 160 Hz as 0x40.
    return [0x00, 0x01 &+ amplitudeHigh, 0x40 &+ amplitudeLowHigh, amplitudeLow]
  }
}
