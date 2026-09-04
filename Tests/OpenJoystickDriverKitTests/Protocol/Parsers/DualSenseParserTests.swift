import Foundation
import Testing

@testable import OpenJoystickDriverKit

private func makeDualSenseUSBReport(
  leftStickX: UInt8 = 128,
  leftStickY: UInt8 = 128,
  rightStickX: UInt8 = 128,
  rightStickY: UInt8 = 128,
  leftTrigger: UInt8 = 0,
  rightTrigger: UInt8 = 0,
  buttons0: UInt8 = 0x08,
  buttons1: UInt8 = 0,
  buttons2: UInt8 = 0
) -> Data {
  var report = [UInt8](repeating: 0, count: 64)
  report[0] = 0x01
  report[1] = leftStickX
  report[2] = leftStickY
  report[3] = rightStickX
  report[4] = rightStickY
  report[5] = leftTrigger
  report[6] = rightTrigger
  report[8] = buttons0
  report[9] = buttons1
  report[10] = buttons2
  return Data(report)
}

private func dualSenseBluetoothCRC32(_ report: [UInt8]) -> UInt32 {
  var crc = updateCRC32(0xFFFF_FFFF, byte: 0xA1)
  for byte in report.dropLast(4) { crc = updateCRC32(crc, byte: byte) }
  return ~crc
}

private func updateCRC32(_ current: UInt32, byte: UInt8) -> UInt32 {
  var crc = current ^ UInt32(byte)
  for _ in 0..<8 { if crc & 1 == 1 { crc = (crc >> 1) ^ 0xEDB8_8320 } else { crc >>= 1 } }
  return crc
}

private func makeDualSenseBluetoothReport(
  leftStickX: UInt8 = 128,
  leftStickY: UInt8 = 128,
  rightStickX: UInt8 = 128,
  rightStickY: UInt8 = 128,
  leftTrigger: UInt8 = 0,
  rightTrigger: UInt8 = 0,
  buttons0: UInt8 = 0x08,
  buttons1: UInt8 = 0,
  buttons2: UInt8 = 0
) -> Data {
  var report = [UInt8](repeating: 0, count: 78)
  report[0] = 0x31
  report[2] = leftStickX
  report[3] = leftStickY
  report[4] = rightStickX
  report[5] = rightStickY
  report[6] = leftTrigger
  report[7] = rightTrigger
  report[9] = buttons0
  report[10] = buttons1
  report[11] = buttons2
  let crc = dualSenseBluetoothCRC32(report)
  report[74] = UInt8(truncatingIfNeeded: crc)
  report[75] = UInt8(truncatingIfNeeded: crc >> 8)
  report[76] = UInt8(truncatingIfNeeded: crc >> 16)
  report[77] = UInt8(truncatingIfNeeded: crc >> 24)
  return Data(report)
}

private func hasEvent(_ events: [ControllerEvent], _ expected: ControllerEvent) -> Bool {
  events.contains(expected)
}

struct DualSenseParserTests {
  @Test func testDualSenseUSBReportParsesPrimaryControls() throws {
    let identifier = DeviceIdentifier(vendorID: 1356, productID: 3302)
    let parser = ParserRegistry().parser(for: identifier)
    _ = try parser.parse(data: makeDualSenseUSBReport())

    let events = try parser.parse(
      data: makeDualSenseUSBReport(
        leftStickX: 255,
        leftStickY: 0,
        rightStickX: 0,
        rightStickY: 255,
        leftTrigger: 255,
        rightTrigger: 128,
        buttons0: 0x28,
        buttons1: 0x30,
        buttons2: 0x03
      )
    )

    #expect(hasEvent(events, .leftStickChanged(x: 1.0, y: 1.0)))
    #expect(hasEvent(events, .rightStickChanged(x: -1.0, y: -1.0)))
    #expect(hasEvent(events, .leftTriggerChanged(1.0)))
    #expect(hasEvent(events, .rightTriggerChanged(128.0 / 255.0)))
    #expect(hasEvent(events, .buttonPressed(.cross)))
    #expect(hasEvent(events, .buttonPressed(.share)))
    #expect(hasEvent(events, .buttonPressed(.options)))
    #expect(hasEvent(events, .buttonPressed(.ps)))
    #expect(hasEvent(events, .buttonPressed(.touchpad)))
  }

  @Test func testDualSenseBluetoothReportParsesPrimaryControlsWithCRC() throws {
    let parser = DualSenseParser()
    _ = try parser.parse(data: makeDualSenseBluetoothReport())

    let events = try parser.parse(
      data: makeDualSenseBluetoothReport(
        leftStickX: 255,
        leftStickY: 0,
        rightStickX: 0,
        rightStickY: 255,
        leftTrigger: 255,
        rightTrigger: 128,
        buttons0: 0x28,
        buttons1: 0x30,
        buttons2: 0x07
      )
    )

    #expect(hasEvent(events, .leftStickChanged(x: 1.0, y: 1.0)))
    #expect(hasEvent(events, .rightStickChanged(x: -1.0, y: -1.0)))
    #expect(hasEvent(events, .leftTriggerChanged(1.0)))
    #expect(hasEvent(events, .rightTriggerChanged(128.0 / 255.0)))
    #expect(hasEvent(events, .buttonPressed(.cross)))
    #expect(hasEvent(events, .buttonPressed(.share)))
    #expect(hasEvent(events, .buttonPressed(.options)))
    #expect(hasEvent(events, .buttonPressed(.ps)))
    #expect(hasEvent(events, .buttonPressed(.touchpad)))
    #expect(hasEvent(events, .buttonPressed(.mute)))
  }

  @Test func testDualSenseUnknownReportIDIsIgnored() throws {
    let parser = DualSenseParser()
    var report = [UInt8](repeating: 0, count: 64)
    report[0] = 0x02
    report[1] = 255
    report[2] = 0
    report[5] = 255
    report[8] = 0x28

    let events = try parser.parse(data: Data(report))

    #expect(events.isEmpty)
  }

  @Test func testDualSenseBluetoothReportRejectsInvalidCRC() throws {
    let parser = DualSenseParser()
    var report = Array(makeDualSenseBluetoothReport(buttons0: 0x28))
    report[77] ^= 0xFF

    do {
      _ = try parser.parse(data: Data(report))
      #expect(Bool(false))
    } catch let error as DualSenseParserError { #expect(error == .invalidBluetoothCRC) } catch {
      #expect(Bool(false))
    }
  }

  @Test func testDualSenseUSBReportParsesMicrophoneMute() throws {
    let parser = DualSenseParser()
    _ = try parser.parse(data: makeDualSenseUSBReport())

    let events = try parser.parse(data: makeDualSenseUSBReport(buttons2: 0x04))

    #expect(hasEvent(events, .buttonPressed(.mute)))
  }

  @Test func testDualSenseProfilesAreExperimentalAndUnverified() {
    let registry = ParserRegistry()
    let identifiers = [
      DeviceIdentifier(vendorID: 1356, productID: 3302),
      DeviceIdentifier(vendorID: 1356, productID: 3570)
    ]

    for identifier in identifiers {
      let profile = registry.runtimeProfile(for: identifier)
      #expect(profile.parserName == "DualSense")
      #expect(profile.protocolVariant.rawValue == "dualSense")
      #expect(profile.quirks == ["touchpad", "microphoneMute"])
    }
  }
}
