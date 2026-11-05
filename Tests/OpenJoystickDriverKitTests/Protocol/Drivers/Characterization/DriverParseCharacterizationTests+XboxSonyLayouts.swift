import Foundation
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

// Report sequences for the Xbox and Sony drivers, built from each driver's documented layout.
// Every sequence opens with a neutral report; each later step changes one field of it.
extension DriverParseCharacterizationTests {
  typealias Subjects = DriverLifecycleCharacterizationTests

  // MARK: - GIP

  /// An 18-byte GIP input payload: buttons at 0–1 (D-pad in the low nibble of 1), 10-bit
  /// triggers at 2 and 4, Int16 sticks at 6–13, Share at 14.
  static let gipNeutralPayload = [UInt8](repeating: 0, count: 18)

  static func gipFrame(_ payload: [UInt8], command: UInt8 = 0x20, options: UInt8 = 0x20) -> [UInt8]
  { [command, options, 0x00, UInt8(payload.count)] + payload }

  static var gipSteps: [Step] {
    let base = gipNeutralPayload
    let payloads =
      [Step("neutral", base)] + bitSteps(base, [(0, 0xFF), (1, 0xF0), (14, 0xFF)])
      + valueSteps(base, offset: 1, mask: 0x0F, prefix: "h", [1, 9, 8, 10, 2, 6, 4, 5, 3, 0])
      + wordSteps(base, offset: 2, prefix: "lt=", [0x1FF, 0x3FF, 0x400, 0])
      + wordSteps(base, offset: 4, prefix: "rt=", [0x1FF, 0x3FF, 0x400, 0])
      + [6, 8, 10, 12].flatMap {
        wordSteps(base, offset: $0, prefix: "s\($0)=", signedWordExtremes)
      }
    return framed(payloads) { gipFrame($1) } + [
      Step("repeat", gipFrame(base)), Step("guide", gipFrame([0x01, 0x5B], command: 0x07)),
      Step("guide-up", gipFrame([0x00, 0x5B], command: 0x07)),
      Step("short", gipFrame(Array(repeating: 0xFF, count: 13))),
      Step("ack-req", gipFrame(bitSteps(base, [(0, 0x10)])[0].bytes, options: 0x30)),
      Step("ack", [0x01, 0x20, 0x01, 0x09, 0x00, 0x20, 0x20, 0x12, 0x00, 0, 0, 0, 0]),
      Step("chunk", [0x20, 0xA0, 0x02, 0x04, 0x00, 0xFF, 0xFF, 0xFF, 0xFF]),
      Step("status", [0x03, 0x20, 0x03, 0x04, 0x80, 0x00, 0x00, 0x00]),
    ]
  }

  /// A frame split across transfers: the header and half the payload, then the rest.
  static var gipSplitSteps: [Step] {
    var pressed = gipNeutralPayload
    pressed[0] = 0x10
    let frame = gipFrame(pressed)
    return [
      Step("neutral", gipFrame(gipNeutralPayload)), Step("head", Array(frame.prefix(10))),
      Step("tail", Array(frame.dropFirst(10))),
    ]
  }

  // MARK: - XUSB

  /// The 20-byte wired report: buttons at 2–3 (D-pad in the low nibble of 2), triggers at 4–5,
  /// Int16 sticks at 6–13.
  static let xusbNeutral: [UInt8] = [0x00, 0x14] + [UInt8](repeating: 0, count: 18)

  static var xusbWiredSteps: [Step] {
    let base = xusbNeutral
    var wrongLength = base
    wrongLength[1] = 0x13
    return [Step("neutral", base)] + bitSteps(base, [(2, 0xF0), (3, 0xFF)])
      + valueSteps(base, offset: 2, mask: 0x0F, prefix: "h", [1, 9, 8, 10, 2, 6, 4, 5, 3, 0])
      + [4, 5].flatMap { valueSteps(base, offset: $0, prefix: "t\($0)=", [0x80, 0xFF, 0]) }
      + [6, 8, 10, 12].flatMap {
        wordSteps(base, offset: $0, prefix: "s\($0)=", signedWordExtremes)
      } + [
        Step("repeat", base), Step("short", Array(bitSteps(base, [(3, 0x10)])[0].bytes.prefix(19))),
        Step("len=13", wrongLength),
      ]
  }

  /// Receiver envelopes: input establishes presence, and a disconnect carries no input state.
  static var xusbReceiverSteps: [Step] {
    let neutral = Array(ProtocolPacketFixtures.XUSBReceiver.padData())
    func pad(_ buttons: UInt16) -> [UInt8] {
      Array(ProtocolPacketFixtures.XUSBReceiver.padData(buttons: buttons))
    }
    var stick = neutral
    stick[10] = 0xFF
    stick[11] = 0x7F
    return [
      Step("early-a", pad(1 << 12)), Step("connect", [0x08, 0x80]), Step("neutral", neutral),
      Step("a", pad(1 << 12)), Step("lsx=max", stick), Step("a+up", pad(1 << 12 | 1)),
      Step("disconnect", [0x08, 0x00]), Step("late-b", pad(1 << 13)), Step("short", [0x00]),
    ]
  }

  // MARK: - XID

  /// The 20-byte XID report: digital byte 2 (D-pad in the low nibble), analog A/B/X/Y at 4–7,
  /// black/white at 8–9, triggers at 10–11, Int16 sticks at 12–19.
  static var xidSteps: [Step] {
    let base: [UInt8] = [0x00, 0x14] + [UInt8](repeating: 0, count: 18)
    return [Step("neutral", base)] + bitSteps(base, [(2, 0xF0)])
      + valueSteps(base, offset: 2, mask: 0x0F, prefix: "h", [1, 9, 8, 10, 2, 6, 4, 5, 3, 0])
      + (4...9).flatMap { valueSteps(base, offset: $0, prefix: "k\($0)=", [0x01, 0xFF, 0]) }
      + [10, 11].flatMap { valueSteps(base, offset: $0, prefix: "t\($0)=", [0x80, 0xFF, 0]) }
      + [12, 14, 16, 18].flatMap {
        wordSteps(base, offset: $0, prefix: "s\($0)=", signedWordExtremes)
      } + [Step("repeat", base), Step("short", Array(repeating: 0xFF, count: 19))]
  }

  // MARK: - Sixaxis

  /// The 49-byte report 0x01: buttons at 2–4 (D-pad in the high nibble of 2), byte sticks at
  /// 6–9, analog L2/R2 at 18–19.
  static var sixaxisSteps: [Step] {
    let base = Array(ProtocolPacketFixtures.DS3.inputReport())
    var unplugged = bitSteps(base, [(3, 0x40)])[0].bytes
    unplugged[1] = 0xFF
    return [Step("neutral", base)] + bitSteps(base, [(2, 0x0F), (3, 0xFF), (4, 0xFF)])
      + valueSteps(
        base,
        offset: 2,
        mask: 0xF0,
        prefix: "h",
        [0x10, 0x30, 0x20, 0x60, 0x40, 0xC0, 0x80, 0x90, 0x50, 0]
      ) + (6...9).flatMap { valueSteps(base, offset: $0, prefix: "s\($0)=", byteExtremes) }
      + [18, 19].flatMap { valueSteps(base, offset: $0, prefix: "t\($0)=", [0x80, 0xFF, 0]) } + [
        Step("repeat", base), Step("byte1=ff", unplugged),
        Step("short", Array(unplugged.prefix(48))),
      ]
  }

  // MARK: - DualShock 4

  /// The 64-byte USB report 0x01: byte sticks at 1–4, buttons at 5–7 (hat code in the low nibble
  /// of 5, neutral 8), triggers at 8–9, sensor timestamp at 10–11, gyro at 13 and accel at 19,
  /// touch count at 33.
  static let dualShock4Neutral: [UInt8] = {
    var report = [UInt8](repeating: 0, count: 64)
    report.replaceSubrange(0..<6, with: [0x01, 0x80, 0x80, 0x80, 0x80, 0x08])
    report.replaceSubrange(13..<25, with: [1, 0, 0xFE, 0xFF, 3, 0, 0, 0x10, 0, 0xF0, 0x20, 0])
    return report
  }()

  /// Every step but the repeat advances the sensor timestamp, so freshness is exercised.
  static var dualShock4USBSteps: [Step] {
    let base = dualShock4Neutral
    var touch = base
    touch.replaceSubrange(33..<43, with: [1, 7, 0x81, 0x10, 0x32, 0x2A, 0x02, 0x20, 0x43, 0x15])
    var battery = base
    battery[30] = 0x1B
    let steps =
      [Step("neutral", base)] + bitSteps(base, [(5, 0xF0), (6, 0xFF), (7, 0xFF)])
      + valueSteps(base, offset: 5, mask: 0x0F, prefix: "h", [0, 1, 2, 3, 4, 5, 6, 7, 0xF, 8])
      + (1...4).flatMap { valueSteps(base, offset: $0, prefix: "s\($0)=", byteExtremes) }
      + [8, 9].flatMap { valueSteps(base, offset: $0, prefix: "t\($0)=", [0x80, 0xFF, 0]) } + [
        Step("touch", touch), Step("battery", battery),
      ]
    let advancing = framed(steps) { index, report in
      var report = report
      report[10] = UInt8(index + 1)
      return report
    }
    let last = advancing.last!.bytes
    return advancing + [
      Step("repeat", last), Step("short", Array(last.prefix(20))),
      Step("minimal", Array(bitSteps(base, [(6, 0x01)])[0].bytes.prefix(10))),
    ]
  }

  /// A Bluetooth report 0x11 around the USB payload, with the 0xA1 CRC appended.
  static func dualShock4Bluetooth(_ usb: [UInt8]) -> [UInt8] {
    var report = [0x11, 0xC0, 0x00] + Array(usb.dropFirst())
    report += [UInt8](repeating: 0, count: 78 - report.count)
    let crc = ProtocolPacketFixtures.DualSense.bluetoothInputCRC32(report)
    for index in 0..<4 { report[74 + index] = UInt8(truncatingIfNeeded: crc >> (8 * index)) }
    return report
  }

  static var dualShock4BluetoothSteps: [Step] {
    let steps = dualShock4USBSteps.filter { !["short", "minimal"].contains($0.label) }
    let bluetooth = framed(steps) { dualShock4Bluetooth($1) }
    var corrupt = bluetooth.last!.bytes
    corrupt[5] ^= 0x10
    return bluetooth + [
      Step("bad-crc", corrupt), Step("short", Array(bluetooth.last!.bytes.prefix(77))),
    ]
  }
}

extension DriverParseCharacterizationTests.Step {
  /// The step's report bytes; empty for an element value.
  var bytes: [UInt8] {
    guard case .report(let data) = input else { return [] }
    return Array(data)
  }
}
