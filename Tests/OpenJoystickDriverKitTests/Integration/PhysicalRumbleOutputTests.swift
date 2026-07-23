import Foundation
import IOKit.hid
import Testing

@testable import OpenJoystickDriverKit

struct PhysicalRumbleOutputTests {
  @Test
  func testSourceBackedParsersExposeExactOutputCapabilities() {
    let gip = GIPParser()
    let xbox360 = Xbox360Parser()
    let ds4 = DS4Parser()
    let dualSense = DualSenseParser()
    let ds3 = DS3Parser()
    let switchPro = SwitchProParser()
    let steamController = SteamControllerParser()

    #expect(
      Set(gip.physicalRumbleMotors)
        == Set([.leftMain, .rightMain, .leftTrigger, .rightTrigger])
    )
    #expect(Set(xbox360.physicalRumbleMotors) == Set([.leftMain, .rightMain]))
    #expect(xbox360.physicalLightingFeatures == [.playerIndicator])
    #expect(Set(ds4.physicalRumbleMotors) == Set([.leftMain, .rightMain]))
    #expect(Set(dualSense.physicalRumbleMotors) == Set([.leftMain, .rightMain]))
    #expect(Set(dualSense.physicalLightingFeatures) == Set([.playerIndicator, .programmableColor]))
    #expect(ds4.physicalLightingFeatures == [.programmableColor])
    #expect(Set(ds3.physicalRumbleMotors) == Set([.leftMain, .rightMain]))
    #expect(ds3.physicalBinaryRumbleMotors == [.rightMain])
    #expect(ds3.physicalLightingFeatures == [.playerIndicator])
    #expect(Set(switchPro.physicalRumbleMotors) == Set([.leftMain, .rightMain]))
    #expect(switchPro.physicalLightingFeatures == [.playerIndicator])
    #expect(steamController.physicalRumbleMotors == [.leftHaptic, .rightHaptic])
    #expect(steamController.physicalLightingFeatures == [.programmableBrightness])
    #expect(hasPhysicalRumble(gip))
    #expect(hasPhysicalRumble(xbox360))
    #expect(hasPhysicalRumble(ds4))
    #expect(hasPhysicalRumble(dualSense))
    #expect(hasPhysicalRumble(ds3))
    #expect(hasPhysicalRumble(switchPro))
    #expect(hasPhysicalRumble(steamController))
  }
  @Test
  func testServiceDescriptionDefaultsToNoPhysicalOutputCapabilities() {
    let description = ApplicationServiceDeviceDescription(
      name: "Test",
      vendorID: 1,
      productID: 2,
      parser: "Test",
      connection: "USB",
      serialNumber: nil
    )

    #expect(description.physicalOutputCapabilities == .none)
  }
  @Test
  func testServiceDescriptionRejectsIncompleteOutputCapabilities() throws {
    let json = """
      {
        "name": "Test",
        "vendorID": 1,
        "productID": 2,
        "parser": "Test",
        "connection": "USB",
        "serialNumber": null,
        "protocolVariant": "unknown",
        "runtimeIdentifier": "0001:0002:M"
      }
      """
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(
        ApplicationServiceDeviceDescription.self,
        from: Data(json.utf8)
      )
    }
  }

  @Test
  func testServiceDescriptionRejectsLegacyRumbleFlag() throws {
    let json = """
      {
        "name": "Test",
        "vendorID": 1,
        "productID": 2,
        "parser": "Test",
        "connection": "USB",
        "serialNumber": null,
        "protocolVariant": "unknown",
        "runtimeIdentifier": "0001:0002:M",
        "supportsPhysicalRumble": true
      }
      """
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(
        ApplicationServiceDeviceDescription.self,
        from: Data(json.utf8)
      )
    }
  }

  @Test
  func testServiceDescriptionDecodesExactOutputCapabilities() throws {
    let capabilities = PhysicalControllerOutputCapabilities(
      rumbleMotors: [.leftMain, .rightMain, .leftTrigger, .rightTrigger],
      lightingFeatures: [.playerIndicator]
    )
    let original = ApplicationServiceDeviceDescription(
      name: "Test",
      vendorID: 1,
      productID: 2,
      parser: "GIP",
      connection: "USB",
      serialNumber: nil,
      physicalOutputCapabilities: capabilities
    )
    let decoded = try JSONDecoder().decode(
      ApplicationServiceDeviceDescription.self,
      from: JSONEncoder().encode(original)
    )

    #expect(decoded.physicalOutputCapabilities.supportsRumble)
    #expect(decoded.physicalOutputCapabilities == capabilities)
  }

  @Test
  func testCapabilitiesRejectLegacyPayloadWithoutEvidence() throws {
    let json = #"{"rumbleMotors":["leftMain","rightMain"],"lightingFeatures":[]}"#
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(
        PhysicalControllerOutputCapabilities.self,
        from: Data(json.utf8)
      )
    }
  }

  @Test
  func testEmptyCapabilitiesCannotClaimOutputEvidence() {
    let capabilities = PhysicalControllerOutputCapabilities(evidence: .hardwareVerified)

    #expect(capabilities.evidence == .unavailable)
  }

  @Test
  func testXbox360PlayerIndicatorsMapToSteadyRingPatterns() {
    #expect(Xbox360Parser.ledPattern(for: .off) == .allOff)
    #expect(Xbox360Parser.ledPattern(for: .player1) == .player1On)
    #expect(Xbox360Parser.ledPattern(for: .player2) == .player2On)
    #expect(Xbox360Parser.ledPattern(for: .player3) == .player3On)
    #expect(Xbox360Parser.ledPattern(for: .player4) == .player4On)
  }

  @Test
  func testVirtualParserAcceptsXboxOneRumbleReports() {
    let command = VirtualRumbleOutputReportParser.parse(
      type: kIOHIDReportTypeOutput,
      reportID: 3,
      bytes: [0x0F, 10, 20, 30, 40, 5, 0, 0]
    )

    let expected = VirtualRumbleCommand(
      left: 30,
      right: 40,
      leftTrigger: 10,
      rightTrigger: 20,
      durationMs: 50
    )
    #expect(command == expected)
  }
  @Test
  func testVirtualParserAcceptsXboxGIPRumbleReports() {
    let reportIDZeroCommand = VirtualRumbleOutputReportParser.parse(
      type: kIOHIDReportTypeOutput,
      reportID: 0,
      bytes: [0x09, 0x00, 0x12, 0x09, 0x00, 0x0F, 10, 20, 30, 40, 5, 0, 0]
    )
    let reportIDNineCommand = VirtualRumbleOutputReportParser.parse(
      type: kIOHIDReportTypeOutput,
      reportID: 9,
      bytes: [0x00, 0x12, 0x09, 0x00, 0x0F, 10, 20, 30, 40, 5, 0, 0]
    )

    let expected = VirtualRumbleCommand(
      left: 30,
      right: 40,
      leftTrigger: 10,
      rightTrigger: 20,
      durationMs: 50
    )
    #expect(reportIDZeroCommand == expected)
    #expect(reportIDNineCommand == expected)
  }
  @Test
  func testVirtualParserAcceptsXbox360RumbleReports() {
    let command = VirtualRumbleOutputReportParser.parse(
      type: kIOHIDReportTypeOutput,
      reportID: 0,
      bytes: [0x00, 0x08, 0x00, 128, 64, 0, 0, 0]
    )

    #expect(command == VirtualRumbleCommand(left: 128, right: 64))
  }
  @Test
  func testVirtualParserAcceptsOJDCompactRumbleReports() {
    let command = VirtualRumbleOutputReportParser.parse(
      type: kIOHIDReportTypeOutput,
      reportID: 0,
      bytes: [0x4F, 1, 2, 3, 4, 0x2C, 0x01]
    )

    let expected = VirtualRumbleCommand(
      left: 1,
      right: 2,
      leftTrigger: 3,
      rightTrigger: 4,
      durationMs: 300
    )
    #expect(command == expected)
  }
  @Test
  func testVirtualParserRejectsUnmarkedRelayInputReports() {
    let command = VirtualRumbleOutputReportParser.parse(
      type: kIOHIDReportTypeOutput,
      reportID: 0,
      bytes: [1, 2, 3, 4, 5, 6]
    )

    #expect(command == nil)
  }
  @Test
  func testDs3PhysicalOutputMatchesLinuxDefaultReport() {
    let report = DS3Parser().physicalRumbleReport(left: 180, right: 90, lt: 255, rt: 64)

    #expect(report.reportID == 0x01)
    #expect(report.bytes.count == 36)
    #expect(Array(report.bytes[0...10]) == [
      0x01, 0x01, 0xFF, 0x01, 0xFF, 180, 0, 0, 0, 0, 0x02,
    ])
    #expect(Array(report.bytes[11...35]) == [
      0xFF, 0x27, 0x10, 0x00, 0x32,
      0xFF, 0x27, 0x10, 0x00, 0x32,
      0xFF, 0x27, 0x10, 0x00, 0x32,
      0xFF, 0x27, 0x10, 0x00, 0x32,
      0, 0, 0, 0, 0,
    ])
  }

  @Test
  func testDs3SmallMotorIsBinaryAndOutputStatePersistsAcrossLedChanges() {
    let parser = DS3Parser()
    let off = parser.physicalRumbleReport(left: 33, right: 0, lt: 0, rt: 0)
    #expect(off.bytes[3] == 0)
    let on = parser.physicalRumbleReport(left: 33, right: 1, lt: 0, rt: 0)
    #expect(on.bytes[3] == 1)

    let led = parser.physicalPlayerIndicatorReport(.player4)
    #expect(led.bytes[3] == 1)
    #expect(led.bytes[5] == 33)
    #expect(led.bytes[10] == 0x10)
    let allOff = parser.physicalPlayerIndicatorReport(.off)
    #expect(allOff.bytes[10] == 0x20)
  }

  @Test
  func testCapabilitiesRejectBinaryMarkersForUnsupportedMotors() {
    let capabilities = PhysicalControllerOutputCapabilities(
      rumbleMotors: [.leftMain],
      binaryRumbleMotors: [.leftMain, .rightMain]
    )

    #expect(capabilities.binaryRumbleMotors == [.leftMain])
  }

  @Test
  func testDualSensePhysicalRumbleUsesExactUSBOutputLayout() {
    let report = DualSenseParser().physicalRumbleReport(left: 180, right: 90, lt: 255, rt: 64)

    #expect(report.reportID == 0x02)
    #expect(report.bytes.count == 63)
    #expect(report.bytes[0] == 0x02)
    #expect(report.bytes[1] == 0x03)
    #expect(report.bytes[3] == 90)
    #expect(report.bytes[4] == 180)
    #expect(report.bytes.dropFirst(5).allSatisfy { $0 == 0 })
  }

  @Test
  func testDualSensePhysicalRumbleUsesSignedBluetoothOutputLayout() {
    let parser = DualSenseParser(prefersBluetooth: true)
    let report = parser.physicalRumbleReport(left: 180, right: 90, lt: 255, rt: 64)

    #expect(report.reportID == 0x31)
    #expect(report.bytes.count == 78)
    #expect(Array(report.bytes[0...6]) == [0x31, 0x00, 0x10, 0x03, 0x00, 90, 180])
    #expect(Array(report.bytes[74...77]) == [0xB9, 0x4F, 0xE2, 0xCD])
    let next = parser.physicalRumbleReport(left: 0, right: 0, lt: 0, rt: 0)
    #expect(next.bytes[1] == 0x10)
  }

  @Test
  func testDualSensePlayerIndicatorUsesCenteredLinuxPatterns() {
    let parser = DualSenseParser()
    let expected: [(PhysicalPlayerIndicator, UInt8)] = [
      (.off, 0x00), (.player1, 0x04), (.player2, 0x0A), (.player3, 0x15),
      (.player4, 0x1B),
    ]

    for (indicator, pattern) in expected {
      let report = parser.physicalPlayerIndicatorReport(indicator)
      #expect(report.reportID == 0x02)
      #expect(report.bytes.count == 63)
      #expect(report.bytes[2] == 0x10)
      #expect(report.bytes[44] == pattern)
    }
  }

  @Test
  func testDualSenseBluetoothPlayerIndicatorIsSigned() {
    let report = DualSenseParser(prefersBluetooth: true)
      .physicalPlayerIndicatorReport(.player3)

    #expect(report.reportID == 0x31)
    #expect(report.bytes[4] == 0x10)
    #expect(report.bytes[46] == 0x15)
    #expect(Array(report.bytes[74...77]) == [0x7B, 0x4C, 0x1C, 0xA9])
  }

  @Test
  func testDs4ColorReportsUseExactUsbAndBluetoothLayouts() {
    let usb = DS4Parser().physicalColorReport(red: 12, green: 34, blue: 56)
    #expect(usb.reportID == 0x05)
    #expect(usb.bytes.count == 32)
    #expect(usb.bytes[1] == 0x02)
    #expect(Array(usb.bytes[6...8]) == [12, 34, 56])

    let bluetooth = DS4Parser(prefersBluetooth: true)
      .physicalColorReport(red: 12, green: 34, blue: 56)
    #expect(bluetooth.reportID == 0x11)
    #expect(bluetooth.bytes[1] == 0xC0)
    #expect(bluetooth.bytes[3] == 0x02)
    #expect(Array(bluetooth.bytes[8...10]) == [12, 34, 56])
    #expect(Array(bluetooth.bytes[74...77]) == [0x6D, 0x86, 0xC4, 0x4D])
  }

  @Test
  func testDualSenseColorReportsUseExactUsbAndBluetoothLayouts() {
    let usb = DualSenseParser().physicalColorReport(red: 12, green: 34, blue: 56)
    #expect(usb.reportID == 0x02)
    #expect(usb.bytes.count == 63)
    #expect(usb.bytes[2] == 0x04)
    #expect(Array(usb.bytes[45...47]) == [12, 34, 56])

    let bluetooth = DualSenseParser(prefersBluetooth: true)
      .physicalColorReport(red: 12, green: 34, blue: 56)
    #expect(bluetooth.reportID == 0x31)
    #expect(bluetooth.bytes[4] == 0x04)
    #expect(Array(bluetooth.bytes[47...49]) == [12, 34, 56])
    #expect(Array(bluetooth.bytes[74...77]) == [0x4C, 0x5A, 0x92, 0x60])
  }

  @Test
  func testDs4PhysicalRumbleReportUsesUSBHIDOutputReport() {
    let report = DS4Parser().physicalRumbleReport(left: 180, right: 90, lt: 255, rt: 64)

    #expect(report.reportID == 0x05)
    #expect(report.bytes.count == 32)
    #expect(report.bytes[0] == 0x05)
    #expect(report.bytes[1] == 0x01)
    #expect(report.bytes[4] == 90)
    #expect(report.bytes[5] == 180)
    #expect(report.bytes.dropFirst(6).allSatisfy { $0 == 0 })
  }
  @Test
  func testDs4PhysicalRumbleReportUsesBluetoothReportAfterBluetoothInput() throws {
    let parser = DS4Parser()
    _ = try parser.parse(
      data: Data([0x11, 0xC0, 0x00, 128, 128, 128, 128, 0x08, 0, 0, 0, 0]
        + [UInt8](repeating: 0, count: 64) + [0x7D, 0x0A, 0x5D, 0x0B])
    )

    let report = parser.physicalRumbleReport(left: 180, right: 90, lt: 255, rt: 64)

    #expect(report.reportID == 0x11)
    #expect(report.bytes.count == 78)
    #expect(report.bytes[0] == 0x11)
    #expect(report.bytes[1] == 0xC0)
    #expect(report.bytes[3] == 0x0F)
    #expect(report.bytes[6] == 90)
    #expect(report.bytes[7] == 180)
    #expect(report.bytes[74...77].contains { $0 != 0 })
  }
  @Test
  func testDs4PreferredBluetoothParserUsesBluetoothPhysicalRumbleBeforeInput() {
    let report = DS4Parser(prefersBluetooth: true).physicalRumbleReport(
      left: 180,
      right: 90,
      lt: 255,
      rt: 64
    )

    #expect(report.reportID == 0x11)
    #expect(report.bytes.count == 78)
    #expect(report.bytes[6] == 90)
    #expect(report.bytes[7] == 180)
  }

  private func hasPhysicalRumble(_ parser: any InputParser) -> Bool {
    parser is PhysicalRumbleOutput || parser is PhysicalHIDRumbleOutput
      || parser is PhysicalHIDFeatureHapticOutput
  }
}
