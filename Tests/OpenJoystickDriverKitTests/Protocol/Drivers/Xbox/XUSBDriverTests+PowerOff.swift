import Foundation
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

// The power-off packet of a receiver slot comes from the description's `receiverPowerOff`; the
// bundled description carries none until the hardware checks pass, so these tests supply one.
extension XUSBDriverTests {
  static let powerOffBytes: [UInt8] = [
    0x00, 0x00, 0x08, 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  ]

  private static func descriptionWithPowerOff() throws -> ProtocolDescription {
    try ProtocolDescriptionFixture.decode(
      family: .xboxXUSB,
      #""rawUSB": true, "defaults": {"receiverPowerOff": "#
        + #"{"bytes": "00 00 08 C0 00 00 00 00 00 00 00 00", "variants": ["Receiver"]}}"#
    )
  }

  private func connectedReceiver(
    description: ProtocolDescription,
    isWirelessReceiver: Bool = true
  ) -> XUSBDriver {
    let driver = XUSBDriver(isWirelessReceiver: isWirelessReceiver, description: description)
    _ = driver.decode(ProtocolPacketFixtures.XUSBReceiver.presenceConnected)
    return driver
  }

  @Test
  func testConnectedReceiverSlotPowersOffWithDescriptionsPacket() throws {
    let driver = connectedReceiver(description: try Self.descriptionWithPowerOff())

    let packet = PhysicalUSBOutputPacket(
      endpoint: 0x01,
      bytes: Self.powerOffBytes,
      timeoutMilliseconds: 2_000
    )
    #expect(driver.powerOffWrites() == [.usb(packet, toleratesRejection: false)])
  }

  @Test
  func testReceiverSlotThatIsNotConnectedDoesNotPowerOff() throws {
    let description = try Self.descriptionWithPowerOff()
    let driver = XUSBDriver(isWirelessReceiver: true, description: description)
    #expect(driver.powerOffWrites().isEmpty)

    _ = driver.decode(ProtocolPacketFixtures.XUSBReceiver.presenceConnected)
    _ = driver.decode(ProtocolPacketFixtures.XUSBReceiver.presenceDisconnected)
    #expect(driver.powerOffWrites().isEmpty)

    _ = driver.decode(ProtocolPacketFixtures.XUSBReceiver.presenceConnected)
    driver.resetProtocolState()
    #expect(driver.powerOffWrites().isEmpty)
  }

  @Test
  func testWiredPadDoesNotPowerOff() throws {
    let description = try Self.descriptionWithPowerOff()

    #expect(XUSBDriver(description: description).powerOffWrites().isEmpty)
  }

  @Test
  func testDescriptionWithoutPacketPowersNothingOff() throws {
    let description = try ProtocolDescriptionFixture.decode(family: .xboxXUSB, #""rawUSB": true"#)

    #expect(connectedReceiver(description: description).powerOffWrites().isEmpty)
  }

  @Test
  func testBundledDescriptionPowersNothingOffUntilHardwareChecksPass() {
    let driver = XUSBDriver(isWirelessReceiver: true)
    _ = driver.decode(ProtocolPacketFixtures.XUSBReceiver.presenceConnected)

    #expect(driver.powerOffWrites().isEmpty)
  }
}
