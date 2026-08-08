import Foundation
import Testing

@testable import OpenJoystickDriverKit

private func makeDS3Report(
  button0: UInt8 = 0,
  button1: UInt8 = 0,
  ps: Bool = false,
  leftX: UInt8 = 128,
  leftY: UInt8 = 128,
  rightX: UInt8 = 128,
  rightY: UInt8 = 128,
  l2Analog: UInt8 = 0,
  r2Analog: UInt8 = 0
) -> Data {
  var report = [UInt8](repeating: 0, count: 49)
  report[0] = 0x01
  report[1] = 0x00
  report[2] = button0
  report[3] = button1
  report[4] = ps ? 0x01 : 0x00
  report[6] = leftX
  report[7] = leftY
  report[8] = rightX
  report[9] = rightY
  report[18] = l2Analog
  report[19] = r2Analog
  return Data(report)
}

private func eventExists(_ events: [ControllerEvent], _ expected: ControllerEvent) -> Bool {
  events.contains(expected)
}

struct DS3ParserTests {
  @Test func testDS3ProfileIsExperimentalAndUnverified() {
    let registry = ParserRegistry()
    let identifier = DeviceIdentifier(vendorID: 1356, productID: 616)
    let profile = registry.runtimeProfile(for: identifier)

    #expect(registry.parserName(for: identifier) == "DS3")
    #expect(profile.protocolVariant == .dualShock3)
    #expect(profile.mappingFlags == ["experimental", "needsHardwareTest"])
    #expect(registry.transportProfile(for: identifier).inputEndpoint == 0x82)
    #expect(registry.transportProfile(for: identifier).outputEndpoint == 0x02)
  }

  @Test func testDS3ReportParsesPrimaryButtonsAndDpad() throws {
    let parser = DS3Parser()
    _ = try parser.parse(data: makeDS3Report())

    let events = try parser.parse(data: makeDS3Report(button0: 0x3F, button1: 0xFF, ps: true))

    #expect(eventExists(events, .buttonPressed(.back)))
    #expect(eventExists(events, .buttonPressed(.leftStick)))
    #expect(eventExists(events, .buttonPressed(.rightStick)))
    #expect(eventExists(events, .buttonPressed(.start)))
    #expect(eventExists(events, .buttonPressed(.l2Digital)))
    #expect(eventExists(events, .buttonPressed(.r2Digital)))
    #expect(eventExists(events, .buttonPressed(.l1)))
    #expect(eventExists(events, .buttonPressed(.r1)))
    #expect(eventExists(events, .buttonPressed(.triangle)))
    #expect(eventExists(events, .buttonPressed(.circle)))
    #expect(eventExists(events, .buttonPressed(.cross)))
    #expect(eventExists(events, .buttonPressed(.square)))
    #expect(eventExists(events, .buttonPressed(.ps)))
    #expect(eventExists(events, .dpadChanged(.northEast)))
  }

  @Test func testDS3ReportParsesSticksAndAnalogTriggers() throws {
    let parser = DS3Parser()
    _ = try parser.parse(data: makeDS3Report())

    let events = try parser.parse(
      data: makeDS3Report(
        leftX: 255,
        leftY: 0,
        rightX: 0,
        rightY: 255,
        l2Analog: 255,
        r2Analog: 128
      )
    )

    #expect(eventExists(events, .leftStickChanged(x: 1.0, y: 1.0)))
    #expect(eventExists(events, .rightStickChanged(x: -1.0, y: -1.0)))
    #expect(eventExists(events, .leftTriggerChanged(1.0)))
    #expect(eventExists(events, .rightTriggerChanged(128.0 / 255.0)))
  }

  @Test func testDS3OperationalFeatureReadRequestsMatchLinuxUsbInitNeed() {
    let requests = DS3Parser().hidStartupFeatureReadRequests()

    #expect(
      requests == [
        PhysicalHIDFeatureReadRequest(reportID: 0xF2, length: 17),
        PhysicalHIDFeatureReadRequest(reportID: 0xF5, length: 8),
      ]
    )
  }

  @Test func testDS3StartupReportsAreTransportScoped() {
    let parser = DS3Parser()

    #expect(
      parser.hidStartupFeatureReadRequests(transport: "USB") == [
        PhysicalHIDFeatureReadRequest(reportID: 0xF2, length: 17),
        PhysicalHIDFeatureReadRequest(reportID: 0xF5, length: 8),
      ]
    )
    #expect(parser.hidStartupFeatureReadRequests(transport: "Bluetooth").isEmpty)
    #expect(parser.hidStartupFeatureReadRequests(transport: nil).isEmpty)
    #expect(parser.hidStartupFeatureReports(transport: "USB").isEmpty)
    #expect(
      parser.hidStartupFeatureReports(transport: "Bluetooth") == [
        PhysicalHIDOutputReport(reportID: 0xF4, bytes: [0xF4, 0x42, 0x03, 0x00, 0x00])
      ]
    )
  }

  @Test func testDS3IgnoresBogusBluetoothStatusReport() throws {
    let parser = DS3Parser()
    var report = Array(makeDS3Report(button0: 0x10, button1: 0x40, leftX: 255, l2Analog: 255))
    report[1] = 0xFF

    let events = try parser.parse(data: Data(report))

    #expect(events.isEmpty)
  }

  @Test func testDS3IgnoresUnsupportedReports() throws {
    let parser = DS3Parser()
    let events = try parser.parse(data: Data([0x02, 0, 0, 0]))

    #expect(events.isEmpty)
  }
}
