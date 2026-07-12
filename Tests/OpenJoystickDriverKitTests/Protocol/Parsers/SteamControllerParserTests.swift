import Foundation
import Testing

@testable import OpenJoystickDriverKit

private func writeInt16LE(_ value: Int16, into bytes: inout [UInt8], at offset: Int) {
  let raw = UInt16(bitPattern: value)
  bytes[offset] = UInt8(truncatingIfNeeded: raw)
  bytes[offset + 1] = UInt8(truncatingIfNeeded: raw >> 8)
}

private func makeSteamControllerReport(
  b8: UInt8 = 0,
  b9: UInt8 = 0,
  b10: UInt8 = 0,
  leftTrigger: UInt8 = 0,
  rightTrigger: UInt8 = 0,
  leftX: Int16 = 0,
  leftY: Int16 = 0,
  rightPadX: Int16 = 0,
  rightPadY: Int16 = 0
) -> Data {
  var report = [UInt8](repeating: 0, count: 64)
  report[0] = 0x01
  report[1] = 0x00
  report[2] = 0x01
  report[3] = 60
  report[8] = b8
  report[9] = b9
  report[10] = b10
  report[11] = leftTrigger
  report[12] = rightTrigger
  writeInt16LE(leftX, into: &report, at: 16)
  writeInt16LE(leftY, into: &report, at: 18)
  writeInt16LE(rightPadX, into: &report, at: 20)
  writeInt16LE(rightPadY, into: &report, at: 22)
  return Data(report)
}

private func makeSteamWirelessReport(status: UInt8) -> Data {
  var report = [UInt8](repeating: 0, count: 64)
  report[0] = 0x01
  report[1] = 0x00
  report[2] = 0x03
  report[3] = 1
  report[4] = status
  return Data(report)
}

private func makeSteamStatusReport() -> Data {
  var report = [UInt8](repeating: 0, count: 64)
  report[0] = 0x01
  report[1] = 0x00
  report[2] = 0x04
  report[3] = 11
  report[16] = 85
  return Data(report)
}

private func eventExists(_ events: [ControllerEvent], _ expected: ControllerEvent) -> Bool {
  events.contains(expected)
}

struct SteamControllerParserTests {
  @Test
  func testSteamControllerProfilesAreExperimentalAndUnverified() {
    let registry = ParserRegistry()
    let identifiers = [
      DeviceIdentifier(vendorID: 10462, productID: 4354),
      DeviceIdentifier(vendorID: 10462, productID: 4418),
    ]

    let wired = registry.runtimeProfile(for: identifiers[0])
    #expect(wired.parserName == "SteamController")
    #expect(wired.protocolVariant == .steamController)
    #expect(wired.mappingFlags == ["lizardMode", "trackpads", "experimental", "needsHardwareTest"])

    let wireless = registry.runtimeProfile(for: identifiers[1])
    #expect(wireless.parserName == "SteamController")
    #expect(wireless.protocolVariant == .steamController)
    #expect(
      wireless.mappingFlags == [
        "lizardMode", "trackpads", "wirelessReceiver", "experimental", "needsHardwareTest",
      ]
    )
  }

  @Test
  func testSteamControllerReportParsesPrimaryControls() throws {
    let parser = ParserRegistry().parser(for: DeviceIdentifier(vendorID: 10462, productID: 4354))
    _ = try parser.parse(data: makeSteamControllerReport())

    let events = try parser.parse(
      data: makeSteamControllerReport(
        b8: 0xFC,
        b9: 0x70,
        b10: 0x44,
        leftTrigger: 255,
        rightTrigger: 128,
        leftX: 32767,
        leftY: -32767,
        rightPadX: -32767,
        rightPadY: 32767
      )
    )

    #expect(eventExists(events, .buttonPressed(.a)))
    #expect(eventExists(events, .buttonPressed(.b)))
    #expect(eventExists(events, .buttonPressed(.x)))
    #expect(eventExists(events, .buttonPressed(.y)))
    #expect(eventExists(events, .buttonPressed(.leftBumper)))
    #expect(eventExists(events, .buttonPressed(.rightBumper)))
    #expect(eventExists(events, .buttonPressed(.back)))
    #expect(eventExists(events, .buttonPressed(.guide)))
    #expect(eventExists(events, .buttonPressed(.start)))
    #expect(eventExists(events, .buttonPressed(.leftStick)))
    #expect(eventExists(events, .buttonPressed(.rightStick)))
    #expect(eventExists(events, .leftTriggerChanged(1.0)))
    #expect(eventExists(events, .rightTriggerChanged(128.0 / 255.0)))
    #expect(eventExists(events, .leftStickChanged(x: 1.0, y: 1.0)))
    #expect(eventExists(events, .rightStickChanged(x: -1.0, y: -1.0)))
  }

  @Test
  func testLeftPadTouchDoesNotCreateVirtualLeftStickMotion() throws {
    let parser = SteamControllerParser()
    _ = try parser.parse(data: makeSteamControllerReport())

    let events = try parser.parse(
      data: makeSteamControllerReport(b10: 0x08, leftX: 32767, leftY: -32767)
    )

    #expect(!eventExists(events, .leftStickChanged(x: 1.0, y: 1.0)))
    #expect(eventExists(events, .buttonPressed(.genericButton4)))
  }

  @Test
  func testLeftPadAndJoyBitAllowsVirtualLeftStickMotion() throws {
    let parser = SteamControllerParser()
    _ = try parser.parse(data: makeSteamControllerReport())

    let events = try parser.parse(
      data: makeSteamControllerReport(b10: 0x88, leftX: 32767, leftY: -32767)
    )

    #expect(eventExists(events, .leftStickChanged(x: 1.0, y: 1.0)))
  }

  @Test
  func testLeftPadAndJoyBitReportsLeftPadTouchButton() throws {
    let parser = SteamControllerParser()
    _ = try parser.parse(data: makeSteamControllerReport())

    let events = try parser.parse(data: makeSteamControllerReport(b10: 0x80))

    #expect(eventExists(events, .buttonPressed(.genericButton4)))
  }

  @Test
  func testSteamControllerReportParsesDpadDirections() throws {
    let parser = SteamControllerParser()
    _ = try parser.parse(data: makeSteamControllerReport())

    let upEvents = try parser.parse(data: makeSteamControllerReport(b9: 0x01))
    let rightEvents = try parser.parse(data: makeSteamControllerReport(b9: 0x02))
    let downEvents = try parser.parse(data: makeSteamControllerReport(b9: 0x08))
    let leftEvents = try parser.parse(data: makeSteamControllerReport(b9: 0x04))

    #expect(eventExists(upEvents, .dpadChanged(.north)))
    #expect(eventExists(rightEvents, .dpadChanged(.east)))
    #expect(eventExists(downEvents, .dpadChanged(.south)))
    #expect(eventExists(leftEvents, .dpadChanged(.west)))
  }

  @Test
  func testSteamControllerDisablesAndRestoresLizardModeWithFeatureReports() {
    let parser = SteamControllerParser()

    let startup = parser.hidStartupFeatureReports()
    #expect(startup.map(\.reportID) == [0, 0])
    #expect(startup.map { $0.bytes.count } == [64, 64])
    #expect(startup[0].bytes[0] == 0x81)
    #expect(Array(startup[1].bytes.prefix(8)) == [0x87, 6, 0x07, 0x07, 0, 0x08, 0x07, 0])

    let shutdown = parser.hidShutdownFeatureReports()
    #expect(shutdown.map(\.reportID) == [0, 0])
    #expect(shutdown.map { $0.bytes.count } == [64, 64])
    #expect(shutdown[0].bytes[0] == 0x85)
    #expect(shutdown[1].bytes[0] == 0x8E)
  }

  @Test
  func testSteamControllerBrightnessMatchesSDLSettingReport() {
    let report = SteamControllerParser().physicalBrightnessReport(197)

    #expect(report.reportID == 0)
    #expect(report.bytes.count == 64)
    #expect(Array(report.bytes.prefix(5)) == [0x87, 3, 45, 197, 0])
    #expect(report.bytes.dropFirst(5).allSatisfy { $0 == 0 })
  }

  @Test
  func testSteamControllerHapticReportsMatchLinuxFeatureCommand() {
    let reports = SteamControllerParser().physicalHapticReports(
      left: 255,
      right: 128,
      durationMs: 450
    )

    #expect(reports.count == 2)
    #expect(reports.allSatisfy { $0.reportID == 0 && $0.bytes.count == 64 })
    #expect(Array(reports[0].bytes.prefix(10)) == [
      0x8F, 8, 1, 0xFF, 0xFF, 0, 0, 7, 0, 0x06,
    ])
    #expect(Array(reports[1].bytes.prefix(10)) == [
      0x8F, 8, 0, 0xFF, 0xFF, 0, 0, 7, 0, 0xF7,
    ])
    #expect(reports.flatMap { $0.bytes.dropFirst(10) }.allSatisfy { $0 == 0 })
  }

  @Test
  func testSteamControllerHapticIntensityAndSafeHoldFallback() {
    let low = SteamControllerParser().physicalHapticReports(left: 1, right: 0, durationMs: 0)

    #expect(low.count == 1)
    #expect(Array(low[0].bytes.prefix(10)) == [
      0x8F, 8, 1, 0xE8, 0xFD, 0, 0, 1, 0, 0xE8,
    ])
    #expect(
      SteamControllerParser().physicalHapticReports(left: 0, right: 0, durationMs: 10).isEmpty
    )
  }

  @Test
  func testSteamWirelessHapticsRequireLogicalControllerConnection() throws {
    let parser = SteamControllerParser(isWirelessReceiver: true)
    #expect(parser.physicalHapticReports(left: 255, right: 0, durationMs: 100).isEmpty)

    _ = try parser.parse(data: makeSteamWirelessReport(status: 0x02))
    #expect(parser.physicalHapticReports(left: 255, right: 0, durationMs: 100).count == 1)

    _ = try parser.parse(data: makeSteamWirelessReport(status: 0x01))
    #expect(parser.physicalHapticReports(left: 255, right: 0, durationMs: 100).isEmpty)
  }

  @Test
  func testSteamWirelessReceiverStatusRequestReport() {
    let wired = SteamControllerParser()
    #expect(wired.inputConnectionStatusRequestReport() == nil)

    let wireless = SteamControllerParser(isWirelessReceiver: true)
    let report = wireless.inputConnectionStatusRequestReport()

    #expect(report?.reportID == 0)
    #expect(report?.bytes.count == 64)
    #expect(report?.bytes.first == 0xB4)
  }

  @Test
  func testSteamControllerTracksWirelessConnectDisconnectLifecycle() throws {
    let parser = SteamControllerParser(isWirelessReceiver: true)
    #expect(parser.requiresInputConnectionBeforeOutput)

    let preConnectEvents = try parser.parse(data: makeSteamControllerReport(b8: 0x80))
    #expect(preConnectEvents.isEmpty)

    let connectEvents = try parser.parse(data: makeSteamWirelessReport(status: 0x02))
    #expect(connectEvents.isEmpty)
    #expect(parser.consumeInputConnectionStateChange() == .connected)
    #expect(parser.consumeInputConnectionStateChange() == nil)

    let inputEvents = try parser.parse(data: makeSteamControllerReport(b8: 0x80))
    #expect(eventExists(inputEvents, .buttonPressed(.a)))

    let disconnectEvents = try parser.parse(data: makeSteamWirelessReport(status: 0x01))
    #expect(disconnectEvents.isEmpty)
    #expect(parser.consumeInputConnectionStateChange() == .disconnected)

    let postDisconnectEvents = try parser.parse(data: makeSteamControllerReport(b8: 0x80))
    #expect(postDisconnectEvents.isEmpty)
  }


  @Test
  func testSteamWirelessStatusReportMarksReceiverConnectedWhenConnectEventWasMissed() throws {
    let parser = SteamControllerParser(isWirelessReceiver: true)

    let statusEvents = try parser.parse(data: makeSteamStatusReport())

    #expect(statusEvents.isEmpty)
    #expect(parser.consumeInputConnectionStateChange() == .connected)

    let inputEvents = try parser.parse(data: makeSteamControllerReport(b8: 0x80))
    #expect(eventExists(inputEvents, .buttonPressed(.a)))
  }

  @Test
  func testSteamControllerIgnoresUnknownNonStateReports() throws {
    let parser = SteamControllerParser()
    var unknownEvent = Array(makeSteamControllerReport())
    unknownEvent[2] = 0x04

    let events = try parser.parse(data: Data(unknownEvent))

    #expect(events.isEmpty)
  }
}
