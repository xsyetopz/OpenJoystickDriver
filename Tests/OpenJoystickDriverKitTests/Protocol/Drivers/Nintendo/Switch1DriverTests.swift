import Foundation
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

struct Switch1DriverTests {
  static let family = PhysicalProtocolID.nintendoSwitch1
  static let model = ControllerModelID(vendorID: 0x057E, productID: 0x2009)

  @Test
  func testSwitchProProfileIsExperimentalAndUnverified() throws {
    let model = ControllerModelID(vendorID: 1406, productID: 8201)
    let profile = try #require(ProtocolDriverRegistry().record(for: model))

    #expect(
      profile.physicalProtocolID == .nintendoSwitch1 && profile.physicalProtocolVariant == nil
    )
    #expect(profile.parameters.isEmpty)
    #expect(profile.transportProfile.inputEndpoint == 0x82)
    #expect(profile.transportProfile.outputEndpoint == 0x02)
  }

  @Test
  func testSwitchProReportParsesPrimaryButtonsAndDpad() throws {
    let parser = Switch1Driver()
    _ = try parser.parseReport(ProtocolPacketFixtures.SwitchPro.inputReport())

    let allPrimaryButtons: UInt32 = 0x00CA_3FCF
    let events = try parser.parseReport(
      ProtocolPacketFixtures.SwitchPro.inputReport(buttons: allPrimaryButtons)
    )

    #expect(events.contains(.press(.south)))
    #expect(events.contains(.press(.east)))
    #expect(events.contains(.press(.west)))
    #expect(events.contains(.press(.north)))
    #expect(events.contains(.press(.leftShoulder)))
    #expect(events.contains(.press(.rightShoulder)))
    #expect(events.contains(.press(.leftTrigger)))
    #expect(events.contains(.press(.rightTrigger)))
    #expect(events.contains(.press(.back)))
    #expect(events.contains(.press(.start)))
    #expect(events.contains(.press(.leftStickClick)))
    #expect(events.contains(.press(.rightStickClick)))
    #expect(events.contains(.press(.guide)))
    #expect(events.contains(.press(.capture)))
    #expect(events.contains(.hat(.northWest)))
  }

  @Test
  func testSwitchProDeclaresItsDigitalTriggers() {
    let capabilities = Switch1Driver(layout: .pro).capabilities
    #expect(capabilities.digitalTriggers == [.leftTrigger, .rightTrigger])
  }

  @Test
  func testSwitchProFaceButtonsUseLinuxPositionalMapping() throws {
    let expectations: [(UInt32, Control)] = [
      (0x0000_0008, .east), (0x0000_0004, .south), (0x0000_0002, .north),
      (0x0000_0001, .west),
    ]

    for (mask, button) in expectations {
      let parser = Switch1Driver()
      _ = try parser.parseReport(ProtocolPacketFixtures.SwitchPro.inputReport())

      let events = try parser.parseReport(
        ProtocolPacketFixtures.SwitchPro.inputReport(buttons: mask)
      )

      #expect(events.contains(.press(button)))
    }
  }

  @Test
  func testSwitchProReportParsesTwelveBitSticks() throws {
    let parser = Switch1Driver()
    _ = try parser.parseReport(ProtocolPacketFixtures.SwitchPro.inputReport())

    let events = try parser.parseReport(
      ProtocolPacketFixtures.SwitchPro.inputReport(sticks: ((4095, 0), (0, 4095)))
    )

    #expect(events.contains(.leftStick(x: 1.0, y: 1.0)))
    #expect(events.contains(.rightStick(x: -1.0, y: -1.0)))
  }

  @Test
  func testSwitchProStartupReportsMatchLinuxUsbInitSlice() {
    let reports = Switch1Driver().startupWrites().hidOutputs

    #expect(reports.map(\.reportID) == ProtocolPacketFixtures.SwitchPro.usbStartupReportIDs)
    #expect(
      reports.map { Array($0.bytes.prefix(2)) } == [
        [0x01, 0x00], [0x01, 0x01], [0x01, 0x02], [0x01, 0x03], [0x01, 0x04],
      ]
    )
    #expect(
      Array(reports[0].bytes[2...9]) == ProtocolPacketFixtures.SwitchPro.neutralRumble
        + ProtocolPacketFixtures.SwitchPro.neutralRumble
    )
    #expect(reports[0].bytes[10] == 0x03)
    #expect(reports[0].bytes[11] == 0x30)
    #expect(reports[1].bytes[10] == 0x40)
    #expect(reports[2].bytes[10] == 0x48)
    #expect(reports[2].bytes[11] == 0x01)
    #expect(reports[1].bytes[11] == 0x01)
  }

  @Test
  func testSwitchProUsbHandshakeIsDescriptionsStartupWrites() {
    let commands = { (layout: ProtocolParameters.Layout?, variant: PhysicalProtocolVariantID) in
      PhysicalProtocolID.nintendoSwitch1.protocolDescription.startupWrites(
        phase: .startup,
        variant: variant,
        parameters: ProtocolParameters(layout: layout)
      ).map { [$0.write].hidOutputs.first?.bytes }
    }
    let expected = ProtocolPacketFixtures.SwitchPro.usbHandshakeCommands.map { [UInt8(0x80), $0] }
    #expect(commands(nil, .usb) == expected)
    #expect(commands(.pro, .usb) == expected)
    #expect(commands(.joyConLeft, .usb).isEmpty)
    #expect(commands(.joyConRight, .usb).isEmpty)
    #expect(commands(.pro, .bluetoothClassic).isEmpty)
  }

  @Test
  func testSwitchProStartupReportsAreTransportScopedAndRateLimited() {
    let bluetooth = Switch1Driver(isBluetooth: true).startupWrites().hidOutputs
    #expect(bluetooth.map(\.reportID) == ProtocolPacketFixtures.SwitchPro.bluetoothStartupReportIDs)
    #expect(
      bluetooth.map { $0.bytes[10] } == ProtocolPacketFixtures.SwitchPro.bluetoothStartupSubcommands
    )
    let reportIDs = Switch1Driver().startupWrites().hidOutputs.map(\.reportID)
    #expect(reportIDs == ProtocolPacketFixtures.SwitchPro.usbStartupReportIDs)
    #expect(Switch1Driver().sessionPlan.hidStartupIntervalNanoseconds == 20_000_000)
    #expect(
      Switch1Driver(isBluetooth: true).sessionPlan.hidStartupIntervalNanoseconds == 60_000_000
    )
    #expect(Switch1Driver().sessionPlan.minimumHIDOutputIntervalNanoseconds == 50_000_000)
  }

  @Test
  func testSwitchProRumbleCodecMatchesLinuxDefaultFrequencyFixtures() {
    #expect(SwitchProRumbleCodec.encode(intensity: 0) == [0x00, 0x01, 0x40, 0x40])
    #expect(SwitchProRumbleCodec.encode(intensity: 128) == [0x00, 0x8B, 0xC0, 0x63])
    #expect(SwitchProRumbleCodec.encode(intensity: 255) == [0x00, 0xC9, 0x40, 0x72])
  }

  @Test
  func testSwitchProRumbleAndPlayerLedReportsPreserveStateAndSequence() {
    let parser = Switch1Driver()
    let rumble = parser.rumblePlan(left: 255, right: 128, lt: 0, rt: 0).onlyReport
    #expect(rumble.reportID == 0x10)
    #expect(rumble.bytes == [0x10, 0x00, 0x00, 0xC9, 0x40, 0x72, 0x00, 0x8B, 0xC0, 0x63])

    let player = parser.encoded(.setPlayerIndicator(.player3)).onlyReport
    #expect(player.reportID == 0x01)
    #expect(Array(player.bytes[0...9]) == [0x01, 0x01] + Array(rumble.bytes[2...9]))
    #expect(player.bytes[10] == 0x30)
    #expect(player.bytes[11] == 0x07)
  }

  @Test
  func testSwitchProIgnoresUnsupportedReports() throws {
    let parser = Switch1Driver()
    let events = try parser.parseReport(Data([0x3F, 0, 0, 0]))

    #expect(events == nil)
  }
}
