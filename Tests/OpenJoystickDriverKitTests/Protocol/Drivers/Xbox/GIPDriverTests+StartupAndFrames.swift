import Foundation
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

extension GIPDriverTests {
  @Test
  func testSequencerIncrements() {
    var seq = GIPSequencer()
    #expect(seq.next(for: 5, options: 0x20) == 1)
    #expect(seq.next(for: 5, options: 0x20) == 2)
    // System messages share one counter
    #expect(seq.next(for: 10, options: 0x20) == 3)
    // Security messages have their own counter
    #expect(seq.next(for: 6, options: 0x20) == 1)
    // Vendor messages have their own counter
    #expect(seq.next(for: 9, options: 0x00) == 1)
    #expect(seq.next(for: 5, options: 0x20) == 4)
  }

  @Test
  func testSequencerWrapsAt255() {
    var seq = GIPSequencer()
    for _ in 0..<254 { _ = seq.next(for: 1, options: 0x20) }
    #expect(seq.next(for: 1, options: 0x20) == 255)
    // Sequence 0 is never sent
    #expect(seq.next(for: 1, options: 0x20) == 1)
  }

  @Test
  func testDefaultStartupSequence() {
    #expect(GIPStartupPacket.defaultSequence == [.powerOn, .ledOn, .authDone])
    #expect(GIPStartupPacket.powerOn.packet(sequence: 0) == [5, 32, 0, 1, 0])
    #expect(GIPStartupPacket.ledOn.packet(sequence: 0) == [10, 32, 0, 3, 0, 1, 20])
    #expect(GIPStartupPacket.authDone.packet(sequence: 0) == [6, 32, 0, 2, 1, 0])
  }

  @Test
  func testKeepAlivePolicyDefaultsToEnabledAndCanBeDisabled() {
    #expect(GIPDriver().keepAlivePolicy == .enabled)
    #expect(GIPDriver(keepAlivePolicy: .disabled).keepAlivePolicy == .disabled)
  }

  @Test
  func testXpadXboxOneStartupPackets() {
    #expect(GIPStartupPacket.xboxOneSInit.packet(sequence: 0) == [5, 32, 0, 15, 6])
    #expect(GIPStartupPacket.extraInput.packet(sequence: 1) == [77, 16, 1, 2, 7, 0])
    #expect(
      GIPStartupPacket.horiAck.packet(sequence: 2) == [1, 32, 2, 9, 0, 4, 32, 58, 0, 0, 0, 128, 0]
    )
    #expect(
      GIPStartupPacket.rumbleBegin.packet(sequence: 3) == [
        9, 0, 3, 9, 0, 15, 0, 0, 29, 29, 255, 0, 0,
      ]
    )
    #expect(
      GIPStartupPacket.rumbleEnd.packet(sequence: 4) == [9, 0, 4, 9, 0, 15, 0, 0, 0, 0, 0, 0, 0]
    )
  }

  @Test
  func testAcknowledgementPacketMatchesGIPLayout() {
    #expect(
      GIPDriver.acknowledgementPacket(
        command: GIPCommand.input,
        options: 0x13,
        sequence: 0x55,
        totalLength: 0x1234
      ) == [
        GIPCommand.acknowledge, 0x23, 0x55, 9, 0, GIPCommand.input, 0x23, 0x34, 0x12, 0, 0, 0, 0,
      ]
    )
  }

  @Test
  func testAcknowledgementIsDeferredUntilTransportConsumesIt() throws {
    let parser = GIPDriver()
    let options = GIPOption.acknowledge | 0x03
    let packet = Data([GIPCommand.virtualKey, options, 0x55, 1, 1])

    #expect(try parser.parseReport(packet).contains(.press(.guide)))
    #expect(
      parser.drainPendingWrites().usbBytes == [
        GIPDriver.acknowledgementPacket(
          command: GIPCommand.virtualKey,
          options: options,
          sequence: 0x55,
          totalLength: 1
        )
      ]
    )
    #expect(parser.drainPendingWrites().isEmpty)
  }

  @Test
  func testAuthenticationResponseIsDeferredUntilTransportConsumesIt() throws {
    let parser = GIPDriver()
    let authPayload = Data([
      GIPAuthType.device, GIPAuthType.version, GIPAuthState.devInit.rawValue, 0, 0, 0,
    ])
    let packet = Data([GIPCommand.authenticate, 0, 0x17, UInt8(authPayload.count)]) + authPayload

    #expect(try parser.parseReport(packet) == nil)
    let responses = parser.drainPendingWrites().usbBytes
    #expect(responses.count == 1)
    #expect(responses.first?.prefix(3) == [GIPCommand.authenticate, GIPOption.internal, 1])
    #expect(
      responses.first?[4...6] == [
        GIPAuthType.host, GIPAuthType.version, GIPAuthState.hostInit.rawValue,
      ]
    )
    #expect(parser.drainPendingWrites().isEmpty)
  }

  @Test
  func testParseSplitFrameAcrossTransfers() throws {
    let parser = GIPDriver()
    let packet = ProtocolPacketFixtures.GIP.inputPacket(payload: Data(repeating: 0, count: 14))

    #expect(try parser.parseReport(packet.prefix(7)) == nil)
    #expect(try parser.parseReport(packet.dropFirst(7))?.state == .neutral)
  }

  @Test
  func testParseStackedFramesFromOneTransfer() throws {
    let parser = GIPDriver()
    var pressed = Data(repeating: 0, count: 14)
    pressed[0] = 16
    let events = try parser.parseReport(
      ProtocolPacketFixtures.GIP.inputPacket(payload: Data(repeating: 0, count: 14))
        + ProtocolPacketFixtures.GIP.inputPacket(payload: pressed)
    )

    #expect(events.contains(.press(.faceSouth)))
  }

  @Test
  func testParseExtendedLengthFrameWithEvenHeaderPadding() throws {
    let parser = GIPDriver()
    var payload = Data(repeating: 0, count: 128)
    payload[0] = 16
    let packet = Data([GIPCommand.input, 0, 0, 0x80, 0x81, 0]) + payload

    #expect(try parser.parseReport(packet).contains(.press(.faceSouth)))
  }

  @Test
  func testParseChunkFrameHeaderWithoutBlockingFollowingFrame() throws {
    let parser = GIPDriver()
    let chunk =
      Data([GIPCommand.input, GIPOption.chunk, 0, 14, 0x80, 0]) + Data(repeating: 0, count: 14)
    var pressed = Data(repeating: 0, count: 14)
    pressed[0] = 16

    #expect(try parser.parseReport(chunk) == nil)
    #expect(
      try parser.parseReport(ProtocolPacketFixtures.GIP.inputPacket(payload: pressed)).contains(
        .press(.faceSouth)
      )
    )
  }

  @Test
  func testParseMainInputAllZero() throws {
    let parser = GIPDriver()
    let packet = ProtocolPacketFixtures.GIP.inputPacket(payload: Data(repeating: 0, count: 14))
    let events = try parser.parseReport(packet)
    #expect(events?.state == .neutral)
  }

  @Test
  func testParseMainInputAButton() throws {
    let parser = GIPDriver()
    var payload = Data(repeating: 0, count: 14)
    payload[0] = 16  // A button
    let packet = ProtocolPacketFixtures.GIP.inputPacket(payload: payload)
    let events = try parser.parseReport(packet)
    #expect(events.contains(.press(.faceSouth)))
  }

  @Test
  func testParseMainInputShareButton() throws {
    let parser = GIPDriver()
    var payload = Data(repeating: 0, count: 32)
    payload[14] = 1
    let events = try parser.parseReport(ProtocolPacketFixtures.GIP.inputPacket(payload: payload))
    #expect(events.contains(.press(.share)))

    payload[14] = 0
    let releaseEvents = try parser.parseReport(
      ProtocolPacketFixtures.GIP.inputPacket(payload: payload, sequence: 1)
    )
    #expect(releaseEvents.contains(.release(.share)))
  }

  @Test
  func testParseMainInputMultipleButtons() throws {
    let parser = GIPDriver()
    var payload = Data(repeating: 0, count: 14)
    // buttons0: A(16) + B(32) = 48
    payload[0] = 48
    // buttons1: LB(16) + dpad_up(1) = 17
    payload[1] = 17
    let packet = ProtocolPacketFixtures.GIP.inputPacket(payload: payload)
    let events = try parser.parseReport(packet)
    #expect(events.contains(.press(.faceSouth)))
    #expect(events.contains(.press(.faceEast)))
    #expect(events.contains(.press(.leftShoulder)))
    #expect(events.contains(.hat(.north)))
  }

  @Test
  func testUnknownCMDReturnsEmpty() throws {
    let parser = GIPDriver()
    let packet = Data([3, 32, 1, 4, 32, 0, 0, 0])
    let events = try parser.parseReport(packet)
    #expect(events == nil)
  }

  @Test
  func testParseGuideButtonPressed() throws {
    let parser = GIPDriver()
    let packet = Data([7, 32, 0, 1, 1])
    let events = try parser.parseReport(packet)
    #expect(events.contains(.press(.guide)))
  }

  @Test
  func testParseGuideButtonReleased() throws {
    let parser = GIPDriver()
    let packet = Data([7, 32, 0, 1, 0])
    let events = try parser.parseReport(packet)
    #expect(events.contains(.release(.guide)))
  }

  @Test
  func testParseShortPacketBuffersUntilComplete() throws {
    let parser = GIPDriver()
    #expect(try parser.parseReport(Data([GIPCommand.input, 32])) == nil)
  }

  @Test
  func testParseIncompletePayloadBuffersUntilComplete() throws {
    let parser = GIPDriver()
    #expect(try parser.parseReport(Data([GIPCommand.input, 32, 0, 14, 0, 0])) == nil)
  }

  @Test
  func testTriggerNormalization() throws {
    let parser = GIPDriver()
    var payload = Data(repeating: 0, count: 14)
    // LT = 1023 (max) = 0x03FF LE
    payload[2] = 0xFF  // LT low byte
    payload[3] = 0x03  // LT high byte
    let packet = ProtocolPacketFixtures.GIP.inputPacket(payload: payload)
    let events = try parser.parseReport(packet)
    #expect(events?.state.leftTrigger == .max)
  }

  @Test
  func testStickNormalization() throws {
    let parser = GIPDriver()
    var payload = Data(repeating: 0, count: 14)
    // LSX = Int16(-32768) = full left -> lx ~ -1.0
    payload[6] = 0x00
    payload[7] = 0x80
    // LSY = Int16(-32768) -> ly = -(-32768/32767) ~ +1.0
    payload[8] = 0x00
    payload[9] = 0x80
    let packet = ProtocolPacketFixtures.GIP.inputPacket(payload: payload)
    let events = try parser.parseReport(packet)
    let stick = try #require(events.leftStickYDown)
    #expect(abs(stick.x - (-1.0)) < 0.01)
    #expect(abs(stick.y - 1.0) < 0.01)
  }

  @Test
  func testDpadCombinations() throws {
    let parser = GIPDriver()
    // up+right = 1+8 = 9
    var payload = Data(repeating: 0, count: 14)
    payload[1] = 9
    let packet = ProtocolPacketFixtures.GIP.inputPacket(payload: payload)
    let events = try parser.parseReport(packet)
    #expect(events.contains(.hat(.northEast)))
  }

  @Test
  func testUnhandledReportTypeReturnsEmpty() throws {
    let parser = GIPDriver()
    let packet = Data([99, 32, 0, 2, 0, 0])
    let events = try parser.parseReport(packet)
    #expect(events == nil)
  }

  @Test
  func testRepeatedReportRepeatsTheSnapshot() throws {
    let parser = GIPDriver()
    var payload1 = Data(repeating: 0, count: 14)
    payload1[0] = 16  // A
    let packet1 = ProtocolPacketFixtures.GIP.inputPacket(payload: payload1)
    let events1 = try parser.parseReport(packet1)
    #expect(events1.contains(.press(.faceSouth)))

    // Same report again: the same snapshot, with A still held.
    let events2 = try parser.parseReport(packet1)
    #expect(events2?.state == events1?.state)
  }

  @Test
  func testReleaseClearsHeldButtonAndDoesNotRepeatWhileNeutral() throws {
    let parser = GIPDriver()
    var held = Data(repeating: 0, count: 14)
    held[1] = 1  // D-pad up
    let heldPacket = ProtocolPacketFixtures.GIP.inputPacket(payload: held)
    let pressEvents = try parser.parseReport(heldPacket)
    #expect(pressEvents.contains(.hat(.north)))

    let neutralPacket = ProtocolPacketFixtures.GIP.inputPacket(
      payload: Data(repeating: 0, count: 14),
      sequence: 1
    )
    let releaseEvents = try parser.parseReport(neutralPacket)
    #expect(releaseEvents.contains(.hat(.neutral)))

    let repeatedNeutralEvents = try parser.parseReport(neutralPacket)
    #expect(repeatedNeutralEvents?.state == .neutral)
  }

}
