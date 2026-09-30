import Foundation
import Testing

@testable import OpenJoystickDriverKit

private func le16(_ value: Int16) -> (UInt8, UInt8) {
  let u = UInt16(bitPattern: value)
  return (UInt8(u & 0xFF), UInt8(u >> 8))
}

private func makeXbox360ReportLE(
  buttons: UInt16 = 0,
  lt: UInt8 = 0,
  rt: UInt8 = 0,
  lsx: Int16 = 0,
  lsy: Int16 = 0,
  rsx: Int16 = 0,
  rsy: Int16 = 0
) -> Data {
  var r = [UInt8](repeating: 0, count: 20)
  r[0] = 0x00
  r[1] = 0x14
  r[2] = UInt8(buttons & 0xFF)
  r[3] = UInt8(buttons >> 8)
  r[4] = lt
  r[5] = rt
  let (lsxL, lsxH) = le16(lsx)
  let (lsyL, lsyH) = le16(lsy)
  let (rsxL, rsxH) = le16(rsx)
  let (rsyL, rsyH) = le16(rsy)
  r[6] = lsxL
  r[7] = lsxH
  r[8] = lsyL
  r[9] = lsyH
  r[10] = rsxL
  r[11] = rsxH
  r[12] = rsyL
  r[13] = rsyH
  return Data(r)
}

struct XUSBDriverTests {
  @Test
  func testIgnoresNonInputReportType() throws {
    let parser = XUSBDriver()
    // Type 0x08 = device connected notification on the wireless receiver
    let packet = Data([0x08, 0x14] + [UInt8](repeating: 0, count: 18))
    let events = try parser.parseReport(packet)
    #expect(events == nil)
  }

  @Test
  func testEmptyDataReturnsEmpty() throws {
    let parser = XUSBDriver()
    let events = try parser.parseReport(Data())
    #expect(events == nil)
  }

  @Test
  func testShortReportReturnsEmpty() throws {
    let parser = XUSBDriver()
    let packet = Data([0x00, 0x14, 0x00, 0x00, 0x00])
    let events = try parser.parseReport(packet)
    #expect(events == nil)
  }

  @Test
  func testInvalidLengthByteReturnsEmpty() throws {
    let parser = XUSBDriver()
    var packet = [UInt8](makeXbox360ReportLE(buttons: 1 << 8))
    packet[1] = 0x0E
    let events = try parser.parseReport(Data(packet))
    #expect(events == nil)
  }

  @Test
  func testAllZeroReportIsTheNeutralSnapshot() throws {
    let parser = XUSBDriver()
    let packet = makeXbox360ReportLE()
    let events = try parser.parseReport(packet)
    #expect(events?.state == .neutral)
  }

  @Test
  func testAButtonPressRelease() throws {
    let parser = XUSBDriver()
    // Bit 12 = A (Linux xpad data[3] & BIT(4))
    let press = makeXbox360ReportLE(buttons: 1 << 12)
    let release = makeXbox360ReportLE(buttons: 0)
    let pressEvents = try parser.parseReport(press)
    #expect(pressEvents.contains(.press(.faceSouth)))
    let releaseEvents = try parser.parseReport(release)
    #expect(releaseEvents.contains(.release(.faceSouth)))
  }

  @Test
  func testBxyButtons() throws {
    let parser = XUSBDriver()
    let packet = makeXbox360ReportLE(buttons: (1 << 13) | (1 << 14) | (1 << 15))
    let events = try parser.parseReport(packet)
    #expect(events.contains(.press(.faceEast)))
    #expect(events.contains(.press(.faceWest)))
    #expect(events.contains(.press(.faceNorth)))
  }

  @Test
  func testShoulderAndStickClicks() throws {
    let parser = XUSBDriver()
    // LB=bit8, RB=bit9, L3=bit6, R3=bit7
    let packet = makeXbox360ReportLE(buttons: (1 << 8) | (1 << 9) | (1 << 6) | (1 << 7))
    let events = try parser.parseReport(packet)
    #expect(events.contains(.press(.leftShoulder)))
    #expect(events.contains(.press(.rightShoulder)))
    #expect(events.contains(.press(.leftStickClick)))
    #expect(events.contains(.press(.rightStickClick)))
  }

  @Test
  func testStartBackButtons() throws {
    let parser = XUSBDriver()
    // START=bit4, BACK=bit5
    let packet = makeXbox360ReportLE(buttons: (1 << 4) | (1 << 5))
    let events = try parser.parseReport(packet)
    #expect(events.contains(.press(.menu)))
    #expect(events.contains(.press(.view)))
  }

  @Test
  func testGuideButton() throws {
    let parser = XUSBDriver()
    // GUIDE=bit10 (Linux xpad data[3] & BIT(2))
    let packet = makeXbox360ReportLE(buttons: 1 << 10)
    let events = try parser.parseReport(packet)
    #expect(events.contains(.press(.guide)))
  }

  @Test
  func testDpadDirections() throws {
    let parser = XUSBDriver()
    // up=bit0, down=bit1, left=bit2, right=bit3
    func hat(bits: UInt16) throws -> HatDirection? {
      try parser.parseReport(makeXbox360ReportLE(buttons: bits))?.state.hat
    }
    #expect(try hat(bits: 1) == .north)
    #expect(try hat(bits: 2) == .south)
    #expect(try hat(bits: 4) == .west)
    #expect(try hat(bits: 8) == .east)
    // northEast = up + right
    #expect(try hat(bits: 9) == .northEast)
  }

  @Test
  func testDpadBitsNotFaceButtons() throws {
    let parser = XUSBDriver()
    let packet = makeXbox360ReportLE(buttons: 0x000F)  // all four dpad bits set
    let events = try parser.parseReport(packet)
    #expect(!events.contains(.press(.faceSouth)))
    #expect(!events.contains(.press(.faceEast)))
    #expect(!events.contains(.press(.faceWest)))
    #expect(!events.contains(.press(.faceNorth)))
  }

  @Test
  func testTriggerNormalization() throws {
    let parser = XUSBDriver()
    let state = try #require(try parser.parseReport(makeXbox360ReportLE(lt: 255, rt: 255))?.state)
    #expect(state.leftTrigger == .max)
    #expect(state.rightTrigger == .max)
  }

  @Test
  func testTriggerHalfPress() throws {
    let parser = XUSBDriver()
    let events = try parser.parseReport(makeXbox360ReportLE(lt: 128, rt: 128))
    #expect(abs((events?.state.leftTrigger.normalized ?? 0) - (128.0 / 255.0)) < 0.01)
  }

  @Test
  func testLeftStickFullRight() throws {
    let parser = XUSBDriver()
    let events = try parser.parseReport(makeXbox360ReportLE(lsx: Int16.max))
    #expect(events?.state.leftStick.x == .max)
  }

  @Test
  func testLeftStickFullDownIsCanonicalDown() throws {
    let parser = XUSBDriver()
    // Raw negative LSY, which the remapping frame reads as down-positive 1.
    let events = try parser.parseReport(makeXbox360ReportLE(lsy: Int16.min))
    #expect(events.leftStickYDown?.y == 1.0)
    #expect(events?.state.leftStick.y == .min)
  }

  @Test
  func testRightStickNormalization() throws {
    let parser = XUSBDriver()
    let events = try parser.parseReport(makeXbox360ReportLE(rsx: Int16.min, rsy: Int16.max))
    let stick = try #require(events.rightStickYDown)
    #expect(stick.x == -1.0)
    #expect(stick.y < -0.99)
  }

  @Test
  func testRepeatedReportRepeatsTheSnapshot() throws {
    let parser = XUSBDriver()
    let report = makeXbox360ReportLE(buttons: 1 << 12, lt: 200, lsx: 10_000)
    let first = try parser.parseReport(report)
    let second = try parser.parseReport(report)
    #expect(second?.state == first?.state)
    #expect(second.contains(.press(.faceSouth)))
  }

  @Test
  func testMultipleSimultaneousButtons() throws {
    let parser = XUSBDriver()
    let packet = makeXbox360ReportLE(buttons: (1 << 12) | (1 << 13) | (1 << 8))
    let events = try parser.parseReport(packet)
    #expect(events.contains(.press(.faceSouth)))
    #expect(events.contains(.press(.faceEast)))
    #expect(events.contains(.press(.leftShoulder)))
  }

  @Test
  func testIgnoresConnectionReport() throws {
    let parser = XUSBDriver()
    var bytes = [UInt8](repeating: 0, count: 20)
    bytes[0] = 0x08  // connection notification
    let events = try parser.parseReport(Data(bytes))
    #expect(events == nil)
  }

  @Test
  func testWirelessReceiverLifecycleAndWrappedInput() throws {
    let parser = XUSBDriver(isWirelessReceiver: true)

    #expect(parser.sessionPlan.requiresInputConnectionBeforeOutput)
    // The presence inquiry; XUSBDriverTests+Receiver pins its bytes.
    #expect(parser.startupWrites().count == 1)
    #expect(try parser.parseReport(Data([0x08, 0x80])) == nil)
    #expect(parser.consumeInputConnectionStateChange() == .connected)
    #expect(parser.consumeInputConnectionStateChange() == nil)

    var state = [UInt8](repeating: 0, count: 20)
    state[0] = 0x00
    state[1] = 0x14
    state[3] = 0x10
    let events = try parser.parseReport(Data([0x00, 0x01, 0x00, 0x00] + state))
    #expect(events.contains(.press(.faceSouth)))
    #expect(parser.consumeInputConnectionStateChange() == nil)

    #expect(try parser.parseReport(Data([0x08, 0x00])) == nil)
    #expect(parser.consumeInputConnectionStateChange() == .disconnected)
  }

  @Test
  func testWirelessReceiverSourceBackedOutputPackets() {
    let parser = XUSBDriver(isWirelessReceiver: true)

    #expect(
      parser.rumblePacket(left: 0x40, right: 0x20) == [
        0x00, 0x01, 0x0F, 0xC0, 0x00, 0x40, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00,
      ]
    )
    #expect(
      parser.ledPacket(pattern: .player1On) == [
        0x00, 0x00, 0x08, 0x46, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      ]
    )
    #expect(
      parser.inputConnectionWrites(for: .connected).usbBytes == [
        parser.ledPacket(pattern: .player1On)
      ]
    )
    #expect(parser.inputConnectionWrites(for: .disconnected).isEmpty)
  }

  @Test
  func testWiredStartupLeavesThePlayerSlotToTheManager() {
    let parser = XUSBDriver()

    #expect(parser.startupWrites().isEmpty)
    #expect(parser.sessionPlan.assignsStartupPlayerIndicator)
    #expect(!XUSBDriver(isWirelessReceiver: true).sessionPlan.assignsStartupPlayerIndicator)
    #expect(
      HIDDescriptorDriver(identifier: DeviceIdentifier(vendorID: 1, productID: 2)).startupWrites()
        .isEmpty
    )
  }
}
