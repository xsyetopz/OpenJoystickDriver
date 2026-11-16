import Testing

@testable import OpenJoystickDriverKit

/// The rumble bytes of the drivers whose report layout lives in their protocol description.
struct DescribedRumbleBytesTests {
  private static let rumbleBytes: [(left: UInt8, right: UInt8)] = [
    (0, 0), (0x12, 0x34), (0x40, 0x20), (0xFF, 0xFF),
  ]

  @Test(arguments: rumbleBytes)
  func xusbWiredRumblePacket(motors: (left: UInt8, right: UInt8)) {
    let packet = XUSBDriver(outEndpoint: 0x05)
      .rumblePlan(left: motors.left, right: motors.right, lt: 9, rt: 9).onlyPacket
    #expect(
      packet
        == PhysicalUSBOutputPacket(
          endpoint: 0x05,
          bytes: [0x00, 0x08, 0x00, motors.left, motors.right, 0x00, 0x00, 0x00],
          timeoutMilliseconds: 2_000
        )
    )
  }

  @Test(arguments: rumbleBytes)
  func xusbReceiverRumblePacket(motors: (left: UInt8, right: UInt8)) {
    let packet = XUSBDriver(outEndpoint: 0x05, isWirelessReceiver: true)
      .rumblePlan(left: motors.left, right: motors.right, lt: 9, rt: 9).onlyPacket
    #expect(
      packet
        == PhysicalUSBOutputPacket(
          endpoint: 0x05,
          bytes: [
            0x00, 0x01, 0x0F, 0xC0, 0x00, motors.left, motors.right, 0x00, 0x00, 0x00, 0x00, 0x00,
          ],
          timeoutMilliseconds: 2_000
        )
    )
  }

  @Test
  func xusbTuningSetsRumblePacketTimeout() {
    let driver = XUSBDriver(tuning: .init(usbTransferTimeoutMilliseconds: 750))
    #expect(
      driver.rumblePlan(left: 1, right: 2, lt: 0, rt: 0).onlyPacket.timeoutMilliseconds == 750
    )
  }

  @Test
  func xusbStopRumbleZeroesMotors() {
    let packet = XUSBDriver().encoded(.stopRumble).onlyPacket
    #expect(packet.bytes == [0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
  }

  @Test(arguments: rumbleBytes)
  func nvidiaShieldV103RumbleReport(motors: (left: UInt8, right: UInt8)) {
    let report = NVIDIAShieldDriver(isShield2015: true)
      .rumblePlan(left: motors.left, right: motors.right, lt: 9, rt: 9).onlyReport
    #expect(report.reportID == 0x01)
    #expect(report.bytes == [0x01, 0x00, motors.left, 0x00, motors.right, 0x00, 0x00])
  }

  @Test(arguments: rumbleBytes)
  func gameSirEnhancedRumbleReport(motors: (left: UInt8, right: UInt8)) {
    let report = GameSirDriver(protocol: .enhancedHID)
      .rumblePlan(left: motors.left, right: motors.right, lt: 9, rt: 9).onlyReport
    #expect(report.reportID == 0x0F)
    #expect(
      report.bytes
        == [0x0F, 0x20, 0x66, 0x55, motors.left, motors.right]
        + [UInt8](repeating: 0, count: 58)
    )
  }

  @Test(arguments: rumbleBytes)
  func xidRumbleWritesWholeByteIntensitiesAsRepeatedBytes(motors: (left: UInt8, right: UInt8)) {
    let packet = xidDriver(outEndpoint: 0x07)
      .rumblePlan(left: motors.left, right: motors.right, lt: 9, rt: 9).onlyPacket
    #expect(
      packet
        == PhysicalUSBOutputPacket(
          endpoint: 0x07,
          bytes: [0x00, 0x06, motors.left, motors.left, motors.right, motors.right],
          timeoutMilliseconds: 2_000
        )
    )
  }

  @Test
  func xidRumbleWritesFull16BitIntensity() {
    let intensities = RumbleIntensities(
      lowFrequency: UnipolarValue(0x1234),
      highFrequency: UnipolarValue(0xFEDC)
    )
    let plan = try? xidDriver().encode(.setRumble(intensities, duration: .held))
    #expect(plan.onlyPacket.bytes == [0x00, 0x06, 0x12, 0x34, 0xFE, 0xDC])
  }

  /// A record's template replaces the description's for its controller.
  @Test
  func recordTemplateOverridesDescriptionsTemplate() throws {
    let template = try RumbleOutputTemplate(
      target: .usb(length: 4),
      bytes: [0x00, 0x04, 0x00, 0x00],
      motors: [.lowFrequency: .init(byte: 2), .highFrequency: .init(byte: 3)]
    )
    let driver = xidDriver(outEndpoint: 0x07, rumbleTemplate: template)
    #expect(
      driver.rumblePlan(left: 0x40, right: 0x20, lt: 0, rt: 0).onlyPacket.bytes == [
        0x00, 0x04, 0x40, 0x20,
      ]
    )
  }

  /// The description holds a template for each variant a driver encodes rumble for.
  @Test
  func descriptionsNameTheirRumbleTemplates() throws {
    let xid = try #require(
      PhysicalProtocolID.xboxXID.protocolDescription.rumbleTemplate(variant: .gamepad)
    )
    #expect(xid.target == .usb(length: 6))
    let wired = PhysicalProtocolID.xboxXUSB.protocolDescription.rumbleTemplate(variant: .wired)
    let receiver = PhysicalProtocolID.xboxXUSB.protocolDescription.rumbleTemplate(
      variant: .receiver
    )
    #expect(wired?.target == .usb(length: 8))
    #expect(receiver?.target == .usb(length: 12))
    let shield = PhysicalProtocolID.vendorNVIDIAShield.protocolDescription.rumbleTemplate(
      variant: nil
    )
    #expect(shield?.report == ControllerTemplateReport(kind: .output, reportID: 1, length: 7))
    let gameSir = PhysicalProtocolID.vendorGameSir.protocolDescription
    #expect(
      gameSir.rumbleTemplate(variant: .enhancedHID)?.report
        == ControllerTemplateReport(kind: .output, reportID: 15, length: 64)
    )
    #expect(gameSir.rumbleTemplate(variant: .usb) == nil)
  }
}
