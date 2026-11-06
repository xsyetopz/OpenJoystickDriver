import Foundation
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

// Report sequences for the DualSense, Nintendo, Valve, vendor, and HID-descriptor drivers.
extension DriverParseCharacterizationTests {
  // MARK: - DualSense

  /// The 64-byte USB report 0x01: byte sticks at 1–4, triggers at 5–6, buttons at 8–10 (hat
  /// code in the low nibble of 8, neutral 8), gyro at 16 and accel at 22, touch contacts at 33
  /// and 37 (0x80 is inactive).
  static let dualSenseNeutral: [UInt8] = {
    var report = Array(ProtocolPacketFixtures.DualSense.usbInputReport())
    report.replaceSubrange(16..<28, with: [1, 0, 0xFE, 0xFF, 3, 0, 0, 0x10, 0, 0xF0, 0x20, 0])
    report[33] = 0x80
    report[37] = 0x80
    return report
  }()

  static var dualSenseUSBSteps: [Step] {
    let base = dualSenseNeutral
    return [Step("neutral", base)] + bitSteps(base, [(8, 0xF0), (9, 0xFF), (10, 0xFF)])
      + valueSteps(base, offset: 8, mask: 0x0F, prefix: "h", [0, 1, 2, 3, 4, 5, 6, 7, 0xF, 8])
      + (1...4).flatMap { valueSteps(base, offset: $0, prefix: "s\($0)=", byteExtremes) }
      + [5, 6].flatMap { valueSteps(base, offset: $0, prefix: "t\($0)=", [0x80, 0xFF, 0]) } + [
        Step("repeat", base), Step("short", Array(base.prefix(63))),
      ]
  }

  /// Bluetooth report 0x31 carrying the same fields one byte later, with its CRC.
  static func dualSenseBluetooth(_ usb: [UInt8]) -> [UInt8] {
    var report = [0x31, 0x00] + Array(usb.dropFirst())
    report += [UInt8](repeating: 0, count: 78 - report.count)
    let crc = ProtocolPacketFixtures.DualSense.bluetoothInputCRC32(report)
    for index in 0..<4 { report[74 + index] = UInt8(truncatingIfNeeded: crc >> (8 * index)) }
    return report
  }

  static var dualSenseBluetoothSteps: [Step] {
    let bluetooth = framed(dualSenseUSBSteps.filter { $0.label != "short" }) {
      dualSenseBluetooth($1)
    }
    var corrupt = bluetooth.last!.bytes
    corrupt[10] ^= 0x10
    return bluetooth + [
      Step("bad-crc", corrupt), Step("short", Array(bluetooth.last!.bytes.prefix(77))),
    ]
  }

  // MARK: - Switch 1

  /// The 49-byte full report 0x30: a 24-bit button word at 3–5 (D-pad in the low nibble of 5),
  /// packed 12-bit sticks at 6 and 9 centred on 2048.
  static var switchSteps: [Step] {
    typealias Pro = ProtocolPacketFixtures.SwitchPro
    let base = Array(Pro.inputReport())
    let stickValues: [UInt16] = [0, 1, 4095, 2048]
    func stick(_ name: String, _ sticks: ProtocolPacketFixtures.WordSticks) -> [Step] {
      [Step(name, Pro.inputReport(sticks: sticks))]
    }
    let sticks = stickValues.flatMap { value in
      stick("lx=\(value)", ((value, 2048), (2048, 2048)))
        + stick("ly=\(value)", ((2048, value), (2048, 2048)))
        + stick("rx=\(value)", ((2048, 2048), (value, 2048)))
        + stick("ry=\(value)", ((2048, 2048), (2048, value)))
    }
    return [Step("neutral", base)] + bitSteps(base, [(3, 0xFF), (4, 0xFF), (5, 0xF0)])
      + valueSteps(base, offset: 5, mask: 0x0F, prefix: "h", [2, 6, 4, 5, 1, 9, 8, 10, 3, 0])
      + sticks + [
        Step("repeat", base), Step("short", Array(base.prefix(11))),
        Step("reply", [0x21] + Array(base.dropFirst())),
      ]
  }

  // MARK: - Steam

  /// The 64-byte state report: buttons at 8–10 (D-pad in the low nibble of 9), triggers at
  /// 11–12, Int16 left stick at 16 and right pad at 20.
  static var steamSteps: [Step] {
    let base = Array(ProtocolPacketFixtures.Steam.inputReport())
    return [Step("neutral", base)] + bitSteps(base, [(8, 0xFF), (9, 0xF0), (10, 0xFF)])
      + valueSteps(base, offset: 9, mask: 0x0F, prefix: "h", [1, 3, 2, 10, 8, 12, 4, 5, 9, 0])
      + [11, 12].flatMap { valueSteps(base, offset: $0, prefix: "t\($0)=", [0x80, 0xFF, 0]) }
      + [16, 18, 20, 22].flatMap {
        wordSteps(base, offset: $0, prefix: "s\($0)=", signedWordExtremes)
      } + [
        Step("repeat", base), Step("status", ProtocolPacketFixtures.Steam.statusReport),
        Step("short", Array(base.prefix(63))),
      ]
  }

  // MARK: - Flydigi

  /// The 15-byte report 0x01: signed byte sticks at 1–4, hat code (1–8, 0 neutral) and face
  /// buttons at 9, shoulders at 10, extras at 11, system at 12, triggers at 13–14.
  static var flydigiSteps: [Step] {
    let base: [UInt8] = [0x01] + [UInt8](repeating: 0, count: 14)
    return [Step("neutral", base)]
      + bitSteps(base, [(9, 0xF0), (10, 0xFF), (11, 0xFF), (12, 0xFF)])
      + valueSteps(base, offset: 9, mask: 0x0F, prefix: "h", [1, 2, 3, 4, 5, 6, 7, 8, 9, 0])
      + (1...4).flatMap {
        valueSteps(base, offset: $0, prefix: "s\($0)=", [0x80, 0x81, 0xFF, 0x7F, 0])
      } + [13, 14].flatMap { valueSteps(base, offset: $0, prefix: "t\($0)=", [0x80, 0xFF, 0]) } + [
        Step("repeat", base), Step("short", Array(base.prefix(14))),
      ]
  }

  // MARK: - GameSir

  /// Wired G7-family pads: XUSB state reports plus 64-byte 0x10 telemetry carrying the extra
  /// buttons at 60 and battery at 32–33.
  static var gameSirUSBSteps: [Step] {
    var telemetry = [UInt8](repeating: 0, count: 64)
    telemetry[0] = 0x10
    telemetry[3] = 0x3C
    telemetry[4] = 0xE0
    telemetry[33] = 73
    var charging = telemetry
    charging[32] = 1
    charging[33] = 101
    let xusb = xusbWiredSteps.filter { !["repeat", "short", "len=13"].contains($0.label) }
    return xusb + [Step("xusb-up", xusbNeutral), Step("telemetry", telemetry)]
      + bitSteps(telemetry, [(60, 0xFF)]) + [
        Step("charging", charging), Step("short", Array(telemetry.prefix(63))),
      ]
  }

  /// The 64-byte enhanced report 0x12: byte sticks at 1–4, face buttons and hat code (neutral 8) at
  /// 5, meta buttons at 6, motion counter at 7, triggers at 8–9, gyro at 14 and accel at 20,
  /// battery at 35–36, extras at 60.
  ///
  /// The motion counter advances except on the repeat.
  static var gameSirEnhancedSteps: [Step] {
    var base = [UInt8](repeating: 0, count: 64)
    base.replaceSubrange(0..<6, with: [0x12, 0x80, 0x80, 0x80, 0x80, 0x08])
    base.replaceSubrange(14..<26, with: [1, 0, 0xFE, 0xFF, 3, 0, 0, 0x10, 0, 0xF0, 0x20, 0])
    base[36] = 84
    let steps =
      [Step("neutral", base)] + bitSteps(base, [(5, 0xF0), (6, 0xFF), (60, 0xFF)])
      + valueSteps(base, offset: 5, mask: 0x0F, prefix: "h", [0, 1, 2, 3, 4, 5, 6, 7, 0xF, 8])
      + (1...4).flatMap { valueSteps(base, offset: $0, prefix: "s\($0)=", byteExtremes) }
      + [8, 9].flatMap { valueSteps(base, offset: $0, prefix: "t\($0)=", [0x80, 0xFF, 0]) }
      + valueSteps(base, offset: 35, prefix: "charge=", [1])
    let advancing = framed(steps) { index, report in
      var report = report
      report[7] = UInt8(index + 1)
      return report
    }
    let last = advancing.last!.bytes
    return advancing + [Step("repeat", last), Step("short", Array(last.prefix(63)))]
  }

  // MARK: - HID descriptor

  static func element(
    _ page: UInt32,
    _ usage: UInt32,
    _ value: Int,
    max: Int = 255
  ) -> HIDElementValue {
    HIDElementValue(
      usagePage: page,
      usage: usage,
      logicalMinimum: 0,
      logicalMaximum: max,
      integerValue: value
    )
  }

  /// IOKit element values: buttons 1–12, generic-desktop X/Y/Z/Rx/Ry/Rz over 0–255, and a 0–7 hat
  /// whose out-of-range value is null.
  ///
  /// Raw reports are ignored by this driver.
  static var hidDescriptorSteps: [Step] {
    let buttons = (1...12).flatMap { usage in
      [
        Step("btn\(usage)", element: element(0x09, UInt32(usage), 1)),
        Step("btn\(usage)-up", element: element(0x09, UInt32(usage), 0)),
      ]
    }
    let axes = (0x30...0x35).flatMap { usage in
      [0, 127, 128, 255].map { value in
        Step("u\(String(usage, radix: 16))=\(value)", element: element(0x01, UInt32(usage), value))
      }
    }
    let hat = [0, 1, 2, 3, 4, 5, 6, 7, 8, 15].map { value in
      Step("h\(value)", element: element(0x01, 0x39, value, max: 7))
    }
    return [Step("report", [UInt8](repeating: 0xFF, count: 8))] + buttons + axes + hat + [
      Step("repeat", element: element(0x01, 0x39, 15, max: 7)),
      Step("span0", element: element(0x01, 0x30, 5, max: 0)),
      Step("accel", element: element(0x02, 0xC4, 255)),
      Step("page7", element: element(0x07, 0x04, 1)),
    ]
  }
}
