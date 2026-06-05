import Foundation
import Testing

@testable import OpenJoystickDriverKit

private func writeSwitchStick(x: UInt16, y: UInt16, into report: inout [UInt8], at offset: Int) {
  report[offset] = UInt8(truncatingIfNeeded: x)
  report[offset + 1] = UInt8(truncatingIfNeeded: (x >> 8) | ((y & 0x0F) << 4))
  report[offset + 2] = UInt8(truncatingIfNeeded: y >> 4)
}

private func makeSwitchProReport(
  buttons: UInt32 = 0,
  leftX: UInt16 = 2048,
  leftY: UInt16 = 2048,
  rightX: UInt16 = 2048,
  rightY: UInt16 = 2048
) -> Data {
  var report = [UInt8](repeating: 0, count: 49)
  report[0] = 0x30
  report[3] = UInt8(truncatingIfNeeded: buttons)
  report[4] = UInt8(truncatingIfNeeded: buttons >> 8)
  report[5] = UInt8(truncatingIfNeeded: buttons >> 16)
  writeSwitchStick(x: leftX, y: leftY, into: &report, at: 6)
  writeSwitchStick(x: rightX, y: rightY, into: &report, at: 9)
  return Data(report)
}

private func eventExists(_ events: [ControllerEvent], _ expected: ControllerEvent) -> Bool {
  events.contains(expected)
}

struct SwitchProParserTests {
  @Test
  func testSwitchProProfileIsExperimentalAndUnverified() {
    let registry = ParserRegistry()
    let identifier = DeviceIdentifier(vendorID: 1406, productID: 8201)
    let profile = registry.runtimeProfile(for: identifier)

    #expect(registry.parserName(for: identifier) == "SwitchPro")
    #expect(profile.protocolVariant == .switchPro)
    #expect(profile.mappingFlags == ["usbHandshake", "experimental", "needsHardwareTest"])
    #expect(registry.transportProfile(for: identifier).inputEndpoint == 0x82)
    #expect(registry.transportProfile(for: identifier).outputEndpoint == 0x02)
  }

  @Test
  func testSwitchProReportParsesPrimaryButtonsAndDpad() throws {
    let parser = SwitchProParser()
    _ = try parser.parse(data: makeSwitchProReport())

    let allPrimaryButtons: UInt32 = 0x00CA_3FCF
    let events = try parser.parse(data: makeSwitchProReport(buttons: allPrimaryButtons))

    #expect(eventExists(events, .buttonPressed(.a)))
    #expect(eventExists(events, .buttonPressed(.b)))
    #expect(eventExists(events, .buttonPressed(.x)))
    #expect(eventExists(events, .buttonPressed(.y)))
    #expect(eventExists(events, .buttonPressed(.leftBumper)))
    #expect(eventExists(events, .buttonPressed(.rightBumper)))
    #expect(eventExists(events, .buttonPressed(.l2Digital)))
    #expect(eventExists(events, .buttonPressed(.r2Digital)))
    #expect(eventExists(events, .buttonPressed(.back)))
    #expect(eventExists(events, .buttonPressed(.start)))
    #expect(eventExists(events, .buttonPressed(.leftStick)))
    #expect(eventExists(events, .buttonPressed(.rightStick)))
    #expect(eventExists(events, .buttonPressed(.guide)))
    #expect(eventExists(events, .buttonPressed(.share)))
    #expect(eventExists(events, .dpadChanged(.northWest)))
  }

  @Test
  func testSwitchProFaceButtonsUseLinuxPositionalMapping() throws {
    let expectations: [(UInt32, Button)] = [
      (0x0000_0008, .b),
      (0x0000_0004, .a),
      (0x0000_0002, .y),
      (0x0000_0001, .x),
    ]

    for (mask, button) in expectations {
      let parser = SwitchProParser()
      _ = try parser.parse(data: makeSwitchProReport())

      let events = try parser.parse(data: makeSwitchProReport(buttons: mask))

      #expect(eventExists(events, .buttonPressed(button)))
    }
  }

  @Test
  func testSwitchProReportParsesTwelveBitSticks() throws {
    let parser = SwitchProParser()
    _ = try parser.parse(data: makeSwitchProReport())

    let events = try parser.parse(
      data: makeSwitchProReport(leftX: 4095, leftY: 0, rightX: 0, rightY: 4095)
    )

    #expect(eventExists(events, .leftStickChanged(x: 1.0, y: 1.0)))
    #expect(eventExists(events, .rightStickChanged(x: -1.0, y: -1.0)))
  }

  @Test
  func testSwitchProStartupReportsMatchLinuxUsbInitSlice() {
    let reports = SwitchProParser().hidStartupReports()

    #expect(reports.map(\.reportID) == [0x80, 0x80, 0x80, 0x80, 0x01])
    #expect(reports.map { Array($0.bytes.prefix(2)) } == [
      [0x80, 0x02],
      [0x80, 0x03],
      [0x80, 0x02],
      [0x80, 0x04],
      [0x01, 0x00],
    ])
    #expect(reports.last?.bytes[10] == 0x03)
    #expect(reports.last?.bytes[11] == 0x30)
  }


  @Test
  func testSwitchProSkipsUsbStartupReportsOnBluetoothTransport() {
    let parser = SwitchProParser()

    #expect(parser.hidStartupReports(transport: "Bluetooth").isEmpty)
    #expect(parser.hidStartupReports(transport: nil).isEmpty)
    let reportIDs = parser.hidStartupReports(transport: "USB").map(\.reportID)
    #expect(reportIDs == [0x80, 0x80, 0x80, 0x80, 0x01])
  }

  @Test
  func testSwitchProIgnoresUnsupportedReports() throws {
    let parser = SwitchProParser()
    let events = try parser.parse(data: Data([0x3F, 0, 0, 0]))

    #expect(events.isEmpty)
  }
}
