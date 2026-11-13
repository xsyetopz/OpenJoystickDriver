import Foundation
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

struct SixaxisDriverTests {
  static let family = PhysicalProtocolID.sonySixaxis
  static let model = ControllerModelID(vendorID: 0x054C, productID: 0x0268)

  @Test
  func testDS3ProfileIsExperimentalAndUnverified() throws {
    let model = ControllerModelID(vendorID: 1356, productID: 616)
    let profile = try #require(ProtocolDriverRegistry().record(for: model))

    #expect(profile.physicalProtocolID == .sonySixaxis && profile.physicalProtocolVariant == nil)
    #expect(profile.parameters.isEmpty)
    #expect(profile.transportProfile.inputEndpoint == 0x82)
    #expect(profile.transportProfile.outputEndpoint == 0x02)
  }

  @Test
  func testDS3ReportParsesPrimaryButtonsAndDpad() throws {
    let parser = SixaxisDriver()
    _ = try parser.parseReport(ProtocolPacketFixtures.DS3.inputReport())

    let events = try parser.parseReport(
      ProtocolPacketFixtures.DS3.inputReport(buttons: (0x3F, 0xFF, true))
    )

    #expect(events.contains(.press(.back)))
    #expect(events.contains(.press(.leftStickClick)))
    #expect(events.contains(.press(.rightStickClick)))
    #expect(events.contains(.press(.start)))
    #expect(events.contains(.press(.leftTrigger)))
    #expect(events.contains(.press(.rightTrigger)))
    #expect(events.contains(.press(.leftShoulder)))
    #expect(events.contains(.press(.rightShoulder)))
    #expect(events.contains(.press(.north)))
    #expect(events.contains(.press(.east)))
    #expect(events.contains(.press(.south)))
    #expect(events.contains(.press(.west)))
    #expect(events.contains(.press(.guide)))
    #expect(events.contains(.hat(.northEast)))
  }

  @Test
  func testDS3ReportParsesSticksAndAnalogTriggers() throws {
    let parser = SixaxisDriver()
    _ = try parser.parseReport(ProtocolPacketFixtures.DS3.inputReport())

    let events = try parser.parseReport(
      ProtocolPacketFixtures.DS3.inputReport(sticks: ((255, 0), (0, 255)), triggers: (255, 128))
    )

    #expect(events.contains(.leftStick(x: 1.0, y: -1.0)))
    #expect(events.contains(.rightStick(x: -1.0, y: 1.0)))
    #expect(events.contains(.leftTrigger(1.0)))
    #expect(events.contains(.rightTrigger(128.0 / 255.0)))
  }

  @Test
  func testDS3OperationalFeatureReadRequestsMatchLinuxUsbInitNeed() {
    let requests = SixaxisDriver().startupFeatureReads()

    #expect(
      requests == [
        PhysicalHIDFeatureReadRequest(reportID: 0xF2, length: 17),
        PhysicalHIDFeatureReadRequest(reportID: 0xF5, length: 8),
      ]
    )
  }

  @Test
  func testDS3StartupReportsAreTransportScoped() {
    let usb = SixaxisDriver()
    let bluetooth = SixaxisDriver(isBluetooth: true)

    #expect(
      usb.startupFeatureReads() == [
        PhysicalHIDFeatureReadRequest(reportID: 0xF2, length: 17),
        PhysicalHIDFeatureReadRequest(reportID: 0xF5, length: 8),
      ]
    )
    #expect(bluetooth.startupFeatureReads().isEmpty)
    // The Bluetooth enable report is a startup write in the controller's record.
    #expect(usb.activationWrites().isEmpty)
    #expect(bluetooth.activationWrites().isEmpty)
  }

  /// A USB Sixaxis streams input reports while idle, so a second without one is a stale pad.
  @Test
  func testDS3OverUSBGoesStaleAfterSecondWithoutInput() {
    #expect(SixaxisDriver().sessionPlan.inputReportLivenessTimeoutNanoseconds == 1_000_000_000)
    let bluetooth = SixaxisDriver(isBluetooth: true)
    #expect(bluetooth.sessionPlan.inputReportLivenessTimeoutNanoseconds == nil)
  }

  /// A USB Sixaxis sends no input until its PS button is pressed; over Bluetooth the press is
  /// what connects it.
  @Test
  func testDS3OverUSBStartsInputOnGuidePress() {
    #expect(SixaxisDriver().sessionPlan.inputStartAction == .pressGuide)
    #expect(SixaxisDriver(isBluetooth: true).sessionPlan.inputStartAction == nil)
  }

  @Test
  func testDS3IgnoresBogusBluetoothStatusReport() throws {
    let parser = SixaxisDriver()
    var report = Array(
      ProtocolPacketFixtures.DS3.inputReport(
        buttons: (0x10, 0x40, false),
        sticks: ((255, 128), (128, 128)),
        triggers: (255, 0)
      )
    )
    report[1] = 0xFF

    let events = try parser.parseReport(Data(report))

    #expect(events == nil)
  }

  @Test
  func testDS3IgnoresUnsupportedReports() throws {
    let parser = SixaxisDriver()
    let events = try parser.parseReport(Data([0x02, 0, 0, 0]))

    #expect(events == nil)
  }
}

extension SixaxisDriverTests {
  @Test
  func startBindingFiresForDS3UnderItsBoundLabels() throws {
    let report = ProtocolPacketFixtures.DS3.inputReport(
      buttons: (0x08, 0x00, false),
      sticks: ((128, 128), (128, 128)),
      triggers: (0, 0)
    )
    let event = try #require(try SixaxisDriver().parseReport(Data(report)))

    let changes = RemappingEngineState.changes(from: .neutral, to: event.state)

    #expect(changes == [.button(.start, isPressed: true)])
  }
}
