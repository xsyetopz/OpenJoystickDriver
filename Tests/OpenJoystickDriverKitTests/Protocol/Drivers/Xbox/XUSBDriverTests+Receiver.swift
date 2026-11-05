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
  func testWirelessReceiverInputEstablishesPresenceWithoutNotification() throws {
    let parser = XUSBDriver(isWirelessReceiver: true)

    #expect(try parser.parseReport(Receiver.padData(buttons: 1 << 12)).contains(.press(.south)))
    #expect(parser.consumeInputConnectionStateChange() == .connected)
    #expect(parser.drainPendingWrites().isEmpty)

    #expect(try parser.parseReport(Receiver.presenceConnected) == nil)
    #expect(parser.consumeInputConnectionStateChange() == nil)
    #expect(try parser.parseReport(Receiver.padData(buttons: 1 << 12)).contains(.press(.south)))
    #expect(parser.drainPendingWrites().isEmpty)
  }

  @Test
  func testWirelessReceiverCapturedPacketDecodesControls() throws {
    let parser = XUSBDriver(isWirelessReceiver: true)
    // 045E:02A9 capture: 29-byte envelope with inner header 00 13.
    let captured: [UInt8] = [
      0x00, 0x01, 0x00, 0xF0, 0x00, 0x13, 0x00, 0x00, 0x00, 0x00,
      0x04, 0x01, 0x6E, 0x00, 0xE1, 0x09, 0x0A, 0x04,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ]
    let state = try #require(parser.parseReport(Data(captured))?.state)
    #expect(state.leftStick.x == BipolarValue(260))
    #expect(state.leftStick.y == BipolarValue(-110))
    #expect(state.rightStick.x == BipolarValue(2_529))
    #expect(state.rightStick.y == BipolarValue(-1_034))
    #expect(parser.consumeInputConnectionStateChange() == .connected)

    var pressed = captured
    pressed[6] = 0x11  // D-pad up and Start.
    pressed[7] = 0x11  // A and left shoulder.
    pressed[8] = 0xFF
    pressed[9] = 0x80
    let input = try #require(try parser.parseReport(Data(pressed)))
    #expect(input.holds(.press(.south)))
    #expect(input.holds(.press(.start)))
    #expect(input.holds(.press(.leftShoulder)))
    #expect(input.state.hat == .north)
    #expect(input.state.leftTrigger == .max)
    #expect(input.state.rightTrigger == UnipolarValue(normalized: Float(128) / 255))
  }

  @Test
  func testWirelessReceiverRejectsTruncatedAndNonInputPacketsWithoutConnecting() throws {
    let report = Array(Receiver.padData(buttons: 1 << 12))
    for length in 0..<18 {
      let parser = XUSBDriver(isWirelessReceiver: true)
      #expect(try parser.parseReport(Data(report.prefix(length))) == nil)
      #expect(parser.consumeInputConnectionStateChange() == nil)
    }
    for offset in [1, 4] {
      let parser = XUSBDriver(isWirelessReceiver: true)
      var invalid = report
      invalid[offset] = 0x02
      #expect(try parser.parseReport(Data(invalid)) == nil)
      #expect(parser.consumeInputConnectionStateChange() == nil)
    }
  }

  @Test
  func testWirelessReceiverNeedsOnlyStateBytesButWiredValidationStaysStrict() throws {
    var report = Array(Receiver.padData(buttons: 1 << 12).prefix(18))
    report[5] = 0x13
    let parser = XUSBDriver(isWirelessReceiver: true)
    #expect(try parser.parseReport(Data(report)).contains(.press(.south)))

    let wired = XUSBDriver()
    var wiredReport = Array(report.dropFirst(4))
    #expect(try wired.parseReport(Data(wiredReport)) == nil)
    wiredReport += [UInt8](repeating: 0, count: 6)
    #expect(try wired.parseReport(Data(wiredReport)) == nil)
    wiredReport[1] = 0x14
    #expect(try wired.parseReport(Data(wiredReport)).contains(.press(.south)))
  }

  @Test
  func testWirelessReceiverPresenceAndInputTrackConnectionSequence() throws {
    let parser = XUSBDriver(isWirelessReceiver: true)

    #expect(try parser.parseReport(Receiver.presenceConnected) == nil)
    #expect(parser.consumeInputConnectionStateChange() == .connected)
    #expect(try parser.parseReport(Receiver.padData(buttons: 1 << 12)).contains(.press(.south)))
    #expect(try parser.parseReport(Receiver.padData()).contains(.release(.south)))
    #expect(parser.consumeInputConnectionStateChange() == nil)

    #expect(try parser.parseReport(Receiver.presenceDisconnected) == nil)
    #expect(parser.consumeInputConnectionStateChange() == .disconnected)
    #expect(try parser.parseReport(Receiver.padData(buttons: 1 << 12)).contains(.press(.south)))
    #expect(parser.consumeInputConnectionStateChange() == .connected)
  }

  @Test
  func testWirelessReceiverHeldButtonReemitsAfterReconnect() throws {
    let parser = XUSBDriver(isWirelessReceiver: true)
    _ = try parser.parseReport(Receiver.presenceConnected)
    #expect(try parser.parseReport(Receiver.padData(buttons: 1 << 12)).contains(.press(.south)))

    _ = try parser.parseReport(Receiver.presenceDisconnected)
    _ = try parser.parseReport(Receiver.presenceConnected)
    #expect(parser.consumeInputConnectionStateChange() == .connected)

    #expect(try parser.parseReport(Receiver.padData(buttons: 1 << 12)).contains(.press(.south)))
  }

  @Test
  func testWirelessReceiverResetForgetsPresenceAndHeldInput() throws {
    let parser = XUSBDriver(isWirelessReceiver: true)
    _ = try parser.parseReport(Receiver.presenceConnected)
    _ = try parser.parseReport(Receiver.padData(buttons: 1 << 12))

    parser.resetProtocolState()

    #expect(parser.consumeInputConnectionStateChange() == nil)
    #expect(try parser.parseReport(Receiver.padData(buttons: 1 << 12)).contains(.press(.south)))
    #expect(parser.consumeInputConnectionStateChange() == .connected)
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
