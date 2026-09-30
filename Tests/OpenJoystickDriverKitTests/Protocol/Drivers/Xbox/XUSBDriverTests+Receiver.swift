import Foundation
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

// Xbox 360 wireless receiver slot presence, per Linux xpad `xpad360w_process_packet`.
extension XUSBDriverTests {
  private typealias Receiver = ProtocolPacketFixtures.XUSBReceiver

  private static func inquiry(endpoint: UInt8 = 0x01) -> PhysicalOutputWrite {
    let packet = PhysicalUSBOutputPacket(
      endpoint: endpoint,
      bytes: [0x08, 0x00, 0x0F, 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
      timeoutMilliseconds: 2_000
    )
    return .usb(packet, toleratesRejection: true)
  }

  @Test
  func testWirelessReceiverStartupSendsTolerantPresenceInquiry() {
    let parser = XUSBDriver(outEndpoint: 0x03, isWirelessReceiver: true)

    #expect(parser.startupWrites() == [Self.inquiry(endpoint: 0x03)])
  }

  @Test
  func testWirelessReceiverPadDataBeforePresenceYieldsNothingAndAsksAgain() throws {
    let parser = XUSBDriver(isWirelessReceiver: true)

    #expect(try parser.parseReport(Receiver.padData(buttons: 1 << 12)) == nil)
    #expect(parser.consumeInputConnectionStateChange() == nil)
    #expect(parser.drainPendingWrites() == [Self.inquiry()])

    // Dropped pad data leaves no state behind, so the first report after presence is a change.
    #expect(try parser.parseReport(Receiver.presenceConnected) == nil)
    #expect(parser.consumeInputConnectionStateChange() == .connected)
    #expect(try parser.parseReport(Receiver.padData(buttons: 1 << 12)).contains(.press(.faceSouth)))
    #expect(parser.drainPendingWrites().isEmpty)
  }

  @Test
  func testWirelessReceiverPresenceInquiryResendIsBounded() throws {
    let parser = XUSBDriver(isWirelessReceiver: true)
    var resends: [Int] = []

    for report in 0..<200 {
      _ = try parser.parseReport(Receiver.padData())
      if !parser.drainPendingWrites().isEmpty { resends.append(report) }
    }

    #expect(resends == [0, 16, 32, 48, 64, 80, 96, 112])
  }

  @Test
  func testWirelessReceiverPresenceGatesPadDataSequence() throws {
    let parser = XUSBDriver(isWirelessReceiver: true)

    #expect(try parser.parseReport(Receiver.presenceConnected) == nil)
    #expect(parser.consumeInputConnectionStateChange() == .connected)
    #expect(try parser.parseReport(Receiver.padData(buttons: 1 << 12)).contains(.press(.faceSouth)))
    #expect(try parser.parseReport(Receiver.padData()).contains(.release(.faceSouth)))
    #expect(parser.consumeInputConnectionStateChange() == nil)

    #expect(try parser.parseReport(Receiver.presenceDisconnected) == nil)
    #expect(parser.consumeInputConnectionStateChange() == .disconnected)
    #expect(try parser.parseReport(Receiver.padData(buttons: 1 << 12)) == nil)
    #expect(parser.consumeInputConnectionStateChange() == nil)
  }

  @Test
  func testWirelessReceiverHeldButtonReemitsAfterReconnect() throws {
    let parser = XUSBDriver(isWirelessReceiver: true)
    _ = try parser.parseReport(Receiver.presenceConnected)
    #expect(try parser.parseReport(Receiver.padData(buttons: 1 << 12)).contains(.press(.faceSouth)))

    _ = try parser.parseReport(Receiver.presenceDisconnected)
    _ = try parser.parseReport(Receiver.presenceConnected)
    #expect(parser.consumeInputConnectionStateChange() == .connected)

    #expect(try parser.parseReport(Receiver.padData(buttons: 1 << 12)).contains(.press(.faceSouth)))
  }

  @Test
  func testWirelessReceiverResetForgetsPresenceAndHeldInput() throws {
    let parser = XUSBDriver(isWirelessReceiver: true)
    _ = try parser.parseReport(Receiver.presenceConnected)
    _ = try parser.parseReport(Receiver.padData(buttons: 1 << 12))

    parser.resetProtocolState()

    #expect(parser.consumeInputConnectionStateChange() == nil)
    #expect(try parser.parseReport(Receiver.padData(buttons: 1 << 12)) == nil)
    _ = try parser.parseReport(Receiver.presenceConnected)
    #expect(parser.consumeInputConnectionStateChange() == .connected)
    #expect(try parser.parseReport(Receiver.padData(buttons: 1 << 12)).contains(.press(.faceSouth)))
  }

  /// The manager assigns a receiver slot's ring LED from the pool wired pads share, so the
  /// driver lights nothing itself: two single-slot receivers must not both show player 1.
  @Test
  func testWirelessReceiverSlotLeavesThePlayerSlotToTheManager() throws {
    for slot in 0..<4 {
      let parser = try #require(XUSBDriver(slotOrdinal: slot))
      #expect(parser.sessionPlan.assignsStartupPlayerIndicator)
      #expect(parser.inputConnectionWrites(for: .connected).isEmpty)
    }
    // xpad's receiver LED command is 0x40 + pattern; player 2 is pattern 7.
    let parser = try #require(XUSBDriver(slotOrdinal: 0))
    #expect(try parser.encode(.setPlayerIndicator(.player2)).writes.usbBytes.first?[3] == 0x47)
    #expect(XUSBDriver(slotOrdinal: -1) == nil)
    #expect(XUSBDriver(slotOrdinal: 4) == nil)
  }
}
