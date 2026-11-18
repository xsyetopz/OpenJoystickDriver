import Foundation
import IOKit.hid
import Testing

@testable import OpenJoystickDriverKit

struct PhysicalRumbleOutputTests {
  @Test
  func testSourceBackedParsersExposeExactOutputCapabilities() {
    let gip = GIPDriver()
    let xbox360 = XUSBDriver()
    let xid = xidDriver()
    let ds4 = DualShock4Driver()
    let dualSense = DualSenseDriver()
    let ds3 = SixaxisDriver()
    let switchPro = Switch1Driver()
    let steamController = SteamControllerDriver()

    #expect(
      Set(gip.outputCapabilities.rumbleMotors)
        == Set([.lowFrequency, .highFrequency, .leftTrigger, .rightTrigger])
    )
    #expect(Set(xbox360.outputCapabilities.rumbleMotors) == Set([.lowFrequency, .highFrequency]))
    #expect(Set(xid.outputCapabilities.rumbleMotors) == Set([.lowFrequency, .highFrequency]))
    #expect(xbox360.outputCapabilities.lightingFeatures == [.playerIndicator])
    #expect(Set(ds4.outputCapabilities.rumbleMotors) == Set([.lowFrequency, .highFrequency]))
    #expect(Set(dualSense.outputCapabilities.rumbleMotors) == Set([.lowFrequency, .highFrequency]))
    #expect(
      Set(dualSense.outputCapabilities.lightingFeatures)
        == Set([.playerIndicator, .programmableColor])
    )
    #expect(ds4.outputCapabilities.lightingFeatures == [.programmableColor])
    #expect(Set(ds3.outputCapabilities.rumbleMotors) == Set([.lowFrequency, .highFrequency]))
    #expect(ds3.outputCapabilities.binaryRumbleMotors == [.highFrequency])
    #expect(ds3.outputCapabilities.lightingFeatures == [.playerIndicator])
    #expect(Set(switchPro.outputCapabilities.rumbleMotors) == Set([.lowFrequency, .highFrequency]))
    #expect(switchPro.outputCapabilities.lightingFeatures == [.playerIndicator])
    #expect(steamController.outputCapabilities.rumbleMotors == [.leftHaptic, .rightHaptic])
    #expect(steamController.outputCapabilities.lightingFeatures == [.programmableBrightness])
    #expect(hasPhysicalRumble(gip))
    #expect(hasPhysicalRumble(xbox360))
    #expect(hasPhysicalRumble(xid))
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
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordServer: .system,
      recordAccessRoute: .system
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
        "protocolBinding": "HIDDescriptor",
        "connection": "USB",
        "serialNumber": null,
        "bindingResult": {
          "outcome": "bound", "accessBackend": "iohid", "interfaces": [], "rule": "hid-descriptor",
          "matchedPredicates": ["hid-descriptor-contract"], "rejectedCandidates": []
        },
        "runtimeIdentifier": "0001:0002:M"
      }
      """
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(ApplicationServiceDeviceDescription.self, from: Data(json.utf8))
    }
  }

  @Test
  func testServiceDescriptionRejectsSupportsPhysicalRumbleFlag() throws {
    let json = """
      {
        "name": "Test",
        "vendorID": 1,
        "productID": 2,
        "protocolBinding": "HIDDescriptor",
        "connection": "USB",
        "serialNumber": null,
        "bindingResult": {
          "outcome": "bound", "accessBackend": "iohid", "interfaces": [], "rule": "hid-descriptor",
          "matchedPredicates": ["hid-descriptor-contract"], "rejectedCandidates": []
        },
        "runtimeIdentifier": "0001:0002:M",
        "supportsPhysicalRumble": true
      }
      """
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(ApplicationServiceDeviceDescription.self, from: Data(json.utf8))
    }
  }

  @Test
  func testServiceDescriptionDecodesExactOutputCapabilities() throws {
    let capabilities = PhysicalControllerOutputCapabilities(
      rumbleMotors: [.lowFrequency, .highFrequency, .leftTrigger, .rightTrigger],
      lightingFeatures: [.playerIndicator]
    )
    let original = ApplicationServiceDeviceDescription(
      name: "Test",
      vendorID: 1,
      productID: 2,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      physicalOutputCapabilities: capabilities,
      recordServer: .system,
      recordAccessRoute: .system
    )
    let decoded = try JSONDecoder().decode(
      ApplicationServiceDeviceDescription.self,
      from: JSONEncoder().encode(original)
    )

    #expect(decoded.physicalOutputCapabilities.supportsRumble)
    #expect(decoded.physicalOutputCapabilities == capabilities)
  }

  @Test
  func testXbox360PlayerIndicatorsMapToSteadyRingPatterns() {
    #expect(XUSBDriver.ledPattern(for: .off) == .allOff)
    #expect(XUSBDriver.ledPattern(for: .player1) == .player1On)
    #expect(XUSBDriver.ledPattern(for: .player2) == .player2On)
    #expect(XUSBDriver.ledPattern(for: .player3) == .player3On)
    #expect(XUSBDriver.ledPattern(for: .player4) == .player4On)
  }

  @Test
  func testConsumerCodecDecodesGIPRumbleReportWithCallbackReportIDPrefix() throws {
    let command = try consumerOutput(
      9,
      gipRumbleReport(
        activation: 0x0F,
        leftTrigger: 10,
        rightTrigger: 20,
        left: 30,
        right: 40,
        duration: 5
      ),
      in: XboxOneGIPHIDReportFormat()
    )

    #expect(
      command
        == .consumerRumble(left: 30, right: 40, leftTrigger: 10, rightTrigger: 20, durationMs: 50)
    )
    // The payload after the report ID is exactly the declared 12 bytes.
    #expect(throws: VirtualHostReportError.tooLarge) {
      try consumerOutput(
        9,
        gipRumbleReport(activation: 0x0F, left: 30, right: 40, duration: 5) + [0],
        in: XboxOneGIPHIDReportFormat()
      )
    }
    // The rumble report is numbered; an unnumbered one is not a report the format declares.
    #expect(throws: VirtualHostReportError.unsupported) {
      try consumerOutput(
        0,
        Array(gipRumbleReport(activation: 0x0F)[1...]),
        in: XboxOneGIPHIDReportFormat()
      )
    }
  }

  @Test
  func testDs3PhysicalOutputMatchesLinuxDefaultReport() {
    let report = SixaxisDriver().rumblePlan(left: 180, right: 90, lt: 255, rt: 64).onlyReport

    #expect(report.reportID == 0x01)
    #expect(report.bytes.count == 49)
    #expect(Array(report.bytes[0...10]) == [0x01, 0x01, 0xFF, 0x01, 0xFF, 180, 0, 0, 0, 0, 0x02])
    #expect(
      Array(report.bytes[11...35]) == [
        0xFF, 0x27, 0x10, 0x00, 0x32, 0xFF, 0x27, 0x10, 0x00, 0x32, 0xFF, 0x27, 0x10, 0x00, 0x32,
        0xFF, 0x27, 0x10, 0x00, 0x32, 0, 0, 0, 0, 0,
      ]
    )
    #expect(report.bytes[36...].allSatisfy { $0 == 0 })
  }

  @Test
  func testDs3SmallMotorIsBinaryAndOutputStatePersistsAcrossLedChanges() {
    let parser = SixaxisDriver()
    let off = parser.rumblePlan(left: 33, right: 0, lt: 0, rt: 0).onlyReport
    #expect(off.bytes[3] == 0)
    let on = parser.rumblePlan(left: 33, right: 1, lt: 0, rt: 0).onlyReport
    #expect(on.bytes[3] == 1)

    let led = parser.encoded(.setPlayerIndicator(.player4)).onlyReport
    #expect(led.bytes[3] == 1)
    #expect(led.bytes[5] == 33)
    #expect(led.bytes[10] == 0x10)
    let allOff = parser.encoded(.setPlayerIndicator(.off)).onlyReport
    #expect(allOff.bytes[10] == 0x20)
  }

  @Test
  func testCapabilitiesRejectBinaryMarkersForUnsupportedMotors() {
    let capabilities = PhysicalControllerOutputCapabilities(
      rumbleMotors: [.lowFrequency],
      binaryRumbleMotors: [.lowFrequency, .highFrequency]
    )

    #expect(capabilities.binaryRumbleMotors == [.lowFrequency])
  }

  @Test
  func testDualSensePhysicalRumbleUsesExactUSBOutputLayout() {
    let report = DualSenseDriver().rumblePlan(left: 180, right: 90, lt: 255, rt: 64).onlyReport

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
    let parser = DualSenseDriver(prefersBluetooth: true)
    let report = parser.rumblePlan(left: 180, right: 90, lt: 255, rt: 64).onlyReport

    #expect(report.reportID == 0x31)
    #expect(report.bytes.count == 78)
    #expect(Array(report.bytes[0...6]) == [0x31, 0x00, 0x10, 0x03, 0x00, 90, 180])
    #expect(Array(report.bytes[74...77]) == [0xB9, 0x4F, 0xE2, 0xCD])
    let next = parser.rumblePlan(left: 0, right: 0, lt: 0, rt: 0).onlyReport
    #expect(next.bytes[1] == 0x10)
  }

  @Test
  func testDualSensePlayerIndicatorUsesCenteredLinuxPatterns() {
    let parser = DualSenseDriver()
    let expected: [(PhysicalPlayerIndicator, UInt8)] = [
      (.off, 0x00), (.player1, 0x04), (.player2, 0x0A), (.player3, 0x15), (.player4, 0x1B),
    ]

    for (indicator, pattern) in expected {
      let report = parser.encoded(.setPlayerIndicator(indicator)).onlyReport
      #expect(report.reportID == 0x02)
      #expect(report.bytes.count == 63)
      #expect(report.bytes[2] == 0x10)
      #expect(report.bytes[44] == pattern)
    }
  }

  @Test
  func testDualSenseBluetoothPlayerIndicatorIsSigned() {
    let report = DualSenseDriver(prefersBluetooth: true).encoded(.setPlayerIndicator(.player3))
      .onlyReport

    #expect(report.reportID == 0x31)
    #expect(report.bytes[4] == 0x10)
    #expect(report.bytes[46] == 0x15)
    #expect(Array(report.bytes[74...77]) == [0x7B, 0x4C, 0x1C, 0xA9])
  }

  @Test
  func testDs4ColorReportsUseExactUsbAndBluetoothLayouts() {
    let usb = DualShock4Driver().encoded(.setRGB(ControllerColor(red: 12, green: 34, blue: 56)))
      .onlyReport
    #expect(usb.reportID == 0x05)
    #expect(usb.bytes.count == 32)
    #expect(usb.bytes[1] == 0x02)
    #expect(Array(usb.bytes[6...8]) == [12, 34, 56])

    let bluetooth = DualShock4Driver(prefersBluetooth: true).encoded(
      .setRGB(ControllerColor(red: 12, green: 34, blue: 56))
    ).onlyReport
    #expect(bluetooth.reportID == 0x11)
    #expect(bluetooth.bytes[1] == 0xC4)
    #expect(bluetooth.bytes[3] == 0x02)
    #expect(Array(bluetooth.bytes[8...10]) == [12, 34, 56])
    #expect(Array(bluetooth.bytes[74...77]) == [0xD7, 0xFA, 0x17, 0x24])
  }

  @Test
  func testDualSenseColorReportsUseExactUsbAndBluetoothLayouts() {
    let usb = DualSenseDriver().encoded(.setRGB(ControllerColor(red: 12, green: 34, blue: 56)))
      .onlyReport
    #expect(usb.reportID == 0x02)
    #expect(usb.bytes.count == 63)
    #expect(usb.bytes[2] == 0x04)
    #expect(Array(usb.bytes[45...47]) == [12, 34, 56])

    let bluetooth = DualSenseDriver(prefersBluetooth: true).encoded(
      .setRGB(ControllerColor(red: 12, green: 34, blue: 56))
    ).onlyReport
    #expect(bluetooth.reportID == 0x31)
    #expect(bluetooth.bytes[4] == 0x04)
    #expect(Array(bluetooth.bytes[47...49]) == [12, 34, 56])
    #expect(Array(bluetooth.bytes[74...77]) == [0x4C, 0x5A, 0x92, 0x60])
  }

  @Test
  func testDs4PhysicalRumbleReportUsesUSBHIDOutputReport() {
    let report = DualShock4Driver().rumblePlan(left: 180, right: 90, lt: 255, rt: 64).onlyReport

    #expect(report.reportID == 0x05)
    #expect(report.bytes.count == 32)
    #expect(report.bytes[0] == 0x05)
    #expect(report.bytes[1] == 0x01)
    #expect(report.bytes[4] == 90)
    #expect(report.bytes[5] == 180)
    #expect(report.bytes.dropFirst(6).allSatisfy { $0 == 0 })
  }

  @Test
  func testDs4PhysicalRumbleReportUsesBluetoothReportAfterBluetoothInput() {
    let parser = DualShock4Driver(prefersBluetooth: true)

    let report = parser.rumblePlan(left: 180, right: 90, lt: 255, rt: 64).onlyReport

    #expect(report.reportID == 0x11)
    #expect(report.bytes.count == 78)
    #expect(report.bytes[0] == 0x11)
    #expect(report.bytes[1] == 0xC4)
    #expect(report.bytes[3] == 0x01)
    #expect(report.bytes[6] == 90)
    #expect(report.bytes[7] == 180)
    #expect(report.bytes[74...77].contains { $0 != 0 })
  }

  @Test
  func testDs4PreferredBluetoothParserUsesBluetoothPhysicalRumbleBeforeInput() {
    let report = DualShock4Driver(prefersBluetooth: true).rumblePlan(
      left: 180,
      right: 90,
      lt: 255,
      rt: 64
    ).onlyReport

    #expect(report.reportID == 0x11)
    #expect(report.bytes.count == 78)
    #expect(report.bytes[6] == 90)
    #expect(report.bytes[7] == 180)
  }

  func hasPhysicalRumble(_ parser: any PhysicalProtocolDriver) -> Bool {
    let intensities: [PhysicalRumbleMotor: UInt8] = [.lowFrequency: 1, .leftHaptic: 1]
    return parser.encoded(
      .setRumble(RumbleIntensities(bytes: intensities), duration: .milliseconds(100))
    ) != nil
  }
}
