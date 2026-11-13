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
  func testWirelessReceiverPadDataBeforePresenceConnectsAndDecodes() throws {
    let parser = XUSBDriver(isWirelessReceiver: true)

    #expect(try parser.parseReport(Receiver.padData(buttons: 1 << 12)).contains(.press(.south)))
    #expect(parser.consumeInputConnectionStateChange() == .connected)
    #expect(parser.consumeInputConnectionStateChange() == nil)
    #expect(parser.drainPendingWrites().isEmpty)

    // A later presence report for the same state is not a change.
    #expect(try parser.parseReport(Receiver.presenceConnected) == nil)
    #expect(parser.consumeInputConnectionStateChange() == nil)
  }

  @Test
  func testWirelessReceiverRealCapturesWithInnerLengthByte13DecodeControls() throws {
    let parser = XUSBDriver(isWirelessReceiver: true)

    // 045E:02A9 (PR #54): lsx 260, lsy 110 (up-positive, so down), rsx 2529, rsy 1034.
    let state02A9 = try #require(parser.parseReport(Receiver.capture02A9)?.state)
    #expect(state02A9.leftStick.x == BipolarValue(260))
    #expect(state02A9.leftStick.y == BipolarValue(-110))
    #expect(state02A9.rightStick.x == BipolarValue(2_529))
    #expect(state02A9.rightStick.y == BipolarValue(-1_034))
    #expect(parser.consumeInputConnectionStateChange() == .connected)

    // 045E:0719 (issue #9): lsx 0xE22C, lsy 0xFCEC, rsx 0xEBB4, rsy 0x05CA.
    let state0719 = try #require(parser.parseReport(Receiver.capture0719)?.state)
    #expect(state0719.leftStick.x == BipolarValue(Int16(bitPattern: 0xE22C)))
    #expect(state0719.rightStick.y == BipolarValue(-0x05CA))
    #expect(state0719.leftTrigger == UnipolarValue(normalized: 0))
    #expect(state0719.pressed.isEmpty)
  }

  @Test
  func testWirelessReceiverRealHeaderDecodesButtonsAndTriggers() throws {
    let parser = XUSBDriver(isWirelessReceiver: true)
    // Masks from the issue #9 hardware table: D-pad up 0001 and Start 0010, A 1000 as 0x1000.
    var report = [UInt8](Receiver.capture02A9)
    report[6] = 0x11  // D-pad up and Start.
    report[7] = 0x11  // A and left shoulder.
    report[8] = 0xFF  // Left trigger full.
    report[9] = 0x80  // Right trigger half.
    let input = try #require(try parser.parseReport(Data(report)))
    #expect(input.holds(.press(.south)))
    #expect(input.holds(.press(.start)))
    #expect(input.holds(.press(.leftShoulder)))
    #expect(input.state.hat == .north)
    #expect(input.state.leftTrigger == .max)
    #expect(input.state.rightTrigger == UnipolarValue(normalized: Float(128) / 255))
  }

  @Test
  func testWirelessReceiverIdleReportDoesNotConnectOrDecode() throws {
    let parser = XUSBDriver(isWirelessReceiver: true)

    #expect(try parser.parseReport(Receiver.idleReport) == nil)
    #expect(parser.consumeInputConnectionStateChange() == nil)
  }

  @Test
  func testWiredPadStillRequiresWiredLengthByte() throws {
    let wired = XUSBDriver()
    var report = Array(Receiver.capture02A9.dropFirst(4).prefix(20))
    #expect(report[1] == 0x13)
    #expect(try wired.parseReport(Data(report)) == nil)
    report[1] = 0x14
    #expect(try wired.parseReport(Data(report)) != nil)
  }

  @Test
  func testWirelessReceiverShortOrWrongTypePadDataDoesNotConnect() throws {
    let parser = XUSBDriver(isWirelessReceiver: true)
    var wrongType = Receiver.padData()
    wrongType[4] = 0x01

    #expect(try parser.parseReport(Receiver.padDataTooShort) == nil)
    #expect(try parser.parseReport(wrongType) == nil)
    #expect(parser.consumeInputConnectionStateChange() == nil)
    #expect(parser.drainPendingWrites().isEmpty)
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
  func testWirelessReceiverRealCaptureStateBytesDecode() throws {
    let parser = XUSBDriver(isWirelessReceiver: true)
    let state = try #require(parser.parseReport(Data(Receiver.capture02A9.prefix(18)))?.state)
    #expect(state.leftStick.x == BipolarValue(260))
    #expect(state.rightStick.y == BipolarValue(-1_034))
    #expect(parser.consumeInputConnectionStateChange() == .connected)
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
  func testWirelessReceiverHeadsetPresenceConnects() throws {
    let parser = XUSBDriver(isWirelessReceiver: true)

    #expect(try parser.parseReport(Receiver.presenceConnectedWithHeadset) == nil)
    #expect(parser.consumeInputConnectionStateChange() == .connected)
  }

  @Test
  func testWirelessReceiverDisconnectAfterPadDataResetsState() throws {
    let parser = XUSBDriver(isWirelessReceiver: true)
    _ = try parser.parseReport(Receiver.padData(buttons: 1 << 12))
    #expect(parser.consumeInputConnectionStateChange() == .connected)

    #expect(try parser.parseReport(Receiver.presenceDisconnected) == nil)
    #expect(parser.consumeInputConnectionStateChange() == .disconnected)
    #expect(try parser.parseReport(Receiver.padData(buttons: 1 << 12)).contains(.press(.south)))
  }

  @Test
  func testWirelessReceiverPresenceGatesPadDataSequence() throws {
    let parser = XUSBDriver(isWirelessReceiver: true)

    #expect(try parser.parseReport(Receiver.presenceConnected) == nil)
    #expect(parser.consumeInputConnectionStateChange() == .connected)
    #expect(try parser.parseReport(Receiver.padData(buttons: 1 << 12)).contains(.press(.south)))
    #expect(try parser.parseReport(Receiver.padData()).contains(.release(.south)))
    #expect(parser.consumeInputConnectionStateChange() == nil)

    #expect(try parser.parseReport(Receiver.presenceDisconnected) == nil)
    #expect(parser.consumeInputConnectionStateChange() == .disconnected)
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
  func testWirelessReceiverSlotLeavesPlayerSlotToManager() throws {
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
