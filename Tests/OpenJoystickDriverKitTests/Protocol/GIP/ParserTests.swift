import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct GIPParserTests {
  @Test func testSequencerIncrements() {
    var seq = GIPSequencer()
    #expect(seq.next(for: 5) == 0)
    #expect(seq.next(for: 5) == 1)
    // Different command starts at 0
    #expect(seq.next(for: 32) == 0)
    // Original command continues
    #expect(seq.next(for: 5) == 2)
  }

  @Test func testSequencerWrapsAt255() {
    var seq = GIPSequencer()
    for _ in 0..<255 { _ = seq.next(for: 1) }
    #expect(seq.next(for: 1) == 255)
    #expect(seq.next(for: 1) == 0)
  }

  @Test func testSequencerReset() {
    var seq = GIPSequencer()
    _ = seq.next(for: 5)
    _ = seq.next(for: 5)
    seq.reset(commandID: 5)
    #expect(seq.next(for: 5) == 0)
  }

  @Test func testDefaultStartupSequence() {
    #expect(GIPStartupPacket.defaultSequence == [.powerOn, .ledOn, .authDone])
    #expect(GIPStartupPacket.powerOn.packet(sequence: 0) == [5, 32, 0, 1, 0])
    #expect(GIPStartupPacket.ledOn.packet(sequence: 0) == [10, 32, 0, 3, 0, 1, 20])
    #expect(GIPStartupPacket.authDone.packet(sequence: 0) == [6, 32, 0, 2, 1, 0])
  }

  @Test func testKeepAlivePolicyDefaultsToEnabledAndCanBeDisabled() {
    #expect(GIPParser().keepAlivePolicy == .enabled)
    #expect(GIPParser(keepAlivePolicy: .disabled).keepAlivePolicy == .disabled)
  }

  @Test func testXpadXboxOneStartupPackets() {
    #expect(GIPStartupPacket.xboxOneSInit.packet(sequence: 0) == [5, 32, 0, 15, 6])
    #expect(GIPStartupPacket.extraInput.packet(sequence: 1) == [77, 16, 1, 2, 7, 0])
    #expect(
      GIPStartupPacket.horiAck.packet(sequence: 2) == [1, 32, 2, 9, 0, 4, 32, 58, 0, 0, 0, 128, 0]
    )
    #expect(
      GIPStartupPacket.rumbleBegin.packet(sequence: 3) == [
        9, 0, 3, 9, 0, 15, 0, 0, 29, 29, 255, 0, 0
      ]
    )
    #expect(
      GIPStartupPacket.rumbleEnd.packet(sequence: 4) == [9, 0, 4, 9, 0, 15, 0, 0, 0, 0, 0, 0, 0]
    )
  }

  @Test func testAcknowledgementPacketMatchesGIPLayout() {
    #expect(
      GIPParser.acknowledgementPacket(
        command: GIPCommand.input,
        options: 0x13,
        sequence: 0x55,
        totalLength: 0x1234
      ) == [
        GIPCommand.acknowledge, 0x23, 0x55, 9, 0, GIPCommand.input, 0x23, 0x34, 0x12, 0, 0, 0, 0
      ]
    )
  }

  @Test func testAcknowledgementIsDeferredUntilTransportConsumesIt() throws {
    let parser = GIPParser()
    let options = GIPOption.acknowledge | 0x03
    let packet = Data([GIPCommand.virtualKey, options, 0x55, 1, 1])

    #expect(try parser.parse(data: packet).contains(.buttonPressed(.guide)))
    #expect(
      parser.consumeUSBOutputPackets() == [
        GIPParser.acknowledgementPacket(
          command: GIPCommand.virtualKey,
          options: options,
          sequence: 0x55,
          totalLength: 1
        )
      ]
    )
    #expect(parser.consumeUSBOutputPackets().isEmpty)
  }

  @Test func testAuthenticationResponseIsDeferredUntilTransportConsumesIt() throws {
    let parser = GIPParser()
    let authPayload = Data([
      GIPAuthType.device, GIPAuthType.version, GIPAuthState.devInit.rawValue, 0, 0, 0
    ])
    let packet = Data([GIPCommand.authenticate, 0, 0x17, UInt8(authPayload.count)]) + authPayload

    #expect(try parser.parse(data: packet).isEmpty)
    let responses = parser.consumeUSBOutputPackets()
    #expect(responses.count == 1)
    #expect(responses.first?.prefix(3) == [GIPCommand.authenticate, GIPOption.internal, 0])
    #expect(
      responses.first?[4...6] == [
        GIPAuthType.host, GIPAuthType.version, GIPAuthState.hostInit.rawValue
      ]
    )
    #expect(parser.consumeUSBOutputPackets().isEmpty)
  }

  @Test func testParseSplitFrameAcrossTransfers() throws {
    let parser = GIPParser()
    let packet = inputPacket(payload: Data(repeating: 0, count: 14))

    #expect(try parser.parse(data: packet.prefix(7)).isEmpty)
    #expect(
      try parser.parse(data: packet.dropFirst(7)).contains { event in
        if case .leftStickChanged = event { return true }
        return false
      }
    )
  }

  @Test func testParseStackedFramesFromOneTransfer() throws {
    let parser = GIPParser()
    var pressed = Data(repeating: 0, count: 14)
    pressed[0] = 16
    let events = try parser.parse(
      data: inputPacket(payload: Data(repeating: 0, count: 14)) + inputPacket(payload: pressed)
    )

    #expect(events.contains(.buttonPressed(.a)))
  }

  @Test func testParseExtendedLengthFrameWithEvenHeaderPadding() throws {
    let parser = GIPParser()
    var payload = Data(repeating: 0, count: 128)
    payload[0] = 16
    let packet = Data([GIPCommand.input, 0, 0, 0x80, 0x81, 0]) + payload

    #expect(try parser.parse(data: packet).contains(.buttonPressed(.a)))
  }

  @Test func testParseChunkFrameHeaderWithoutBlockingFollowingFrame() throws {
    let parser = GIPParser()
    let chunk =
      Data([GIPCommand.input, GIPOption.chunk, 0, 14, 0x80, 0]) + Data(repeating: 0, count: 14)
    var pressed = Data(repeating: 0, count: 14)
    pressed[0] = 16

    #expect(try parser.parse(data: chunk).isEmpty)
    #expect(try parser.parse(data: inputPacket(payload: pressed)).contains(.buttonPressed(.a)))
  }

  @Test func testParseMainInputAllZero() throws {
    let parser = GIPParser()
    var packet = Data([0x20, 32, 0, 14])
    packet += Data(repeating: 0, count: 14)
    let events = try parser.parse(data: packet)
    let hasLeftStick = events.contains {
      if case .leftStickChanged = $0 { return true }
      return false
    }
    #expect(hasLeftStick)
  }

  @Test func testParseMainInputAButton() throws {
    let parser = GIPParser()
    var payload = Data(repeating: 0, count: 14)
    payload[0] = 16  // A button
    var packet = Data([0x20, 32, 0, 14])
    packet += payload
    let events = try parser.parse(data: packet)
    #expect(events.contains(.buttonPressed(.a)))
  }

  @Test func testParseMainInputShareButton() throws {
    let parser = GIPParser()
    var payload = Data(repeating: 0, count: 15)
    payload[14] = 1
    var packet = Data([0x20, 32, 0, 15])
    packet += payload
    let events = try parser.parse(data: packet)
    #expect(events.contains(.buttonPressed(.share)))

    payload[14] = 0
    packet = Data([0x20, 32, 1, 15])
    packet += payload
    let releaseEvents = try parser.parse(data: packet)
    #expect(releaseEvents.contains(.buttonReleased(.share)))
  }

  @Test func testParseMainInputMultipleButtons() throws {
    let parser = GIPParser()
    var payload = Data(repeating: 0, count: 14)
    // buttons0: A(16) + B(32) = 48
    payload[0] = 48
    // buttons1: LB(16) + dpad_up(1) = 17
    payload[1] = 17
    var packet = Data([0x20, 32, 0, 14])
    packet += payload
    let events = try parser.parse(data: packet)
    #expect(events.contains(.buttonPressed(.a)))
    #expect(events.contains(.buttonPressed(.b)))
    #expect(events.contains(.buttonPressed(.leftBumper)))
    #expect(events.contains(.dpadChanged(.north)))
  }

  @Test func testUnknownCMDReturnsEmpty() throws {
    let parser = GIPParser()
    let packet = Data([3, 32, 1, 4, 32, 0, 0, 0])
    let events = try parser.parse(data: packet)
    #expect(events.isEmpty)
  }

  @Test func testParseGuideButtonPressed() throws {
    let parser = GIPParser()
    let packet = Data([7, 32, 0, 1, 1])
    let events = try parser.parse(data: packet)
    #expect(events.contains(.buttonPressed(.guide)))
  }

  @Test func testParseGuideButtonReleased() throws {
    let parser = GIPParser()
    let packet = Data([7, 32, 0, 1, 0])
    let events = try parser.parse(data: packet)
    #expect(events.contains(.buttonReleased(.guide)))
  }

  @Test func testParseShortPacketBuffersUntilComplete() throws {
    let parser = GIPParser()
    #expect(try parser.parse(data: Data([GIPCommand.input, 32])).isEmpty)
  }

  @Test func testParseIncompletePayloadBuffersUntilComplete() throws {
    let parser = GIPParser()
    #expect(try parser.parse(data: Data([GIPCommand.input, 32, 0, 14, 0, 0])).isEmpty)
  }

  @Test func testTriggerNormalization() throws {
    let parser = GIPParser()
    var payload = Data(repeating: 0, count: 14)
    // LT = 1023 (max) = 0x03FF LE
    payload[2] = 0xFF  // LT low byte
    payload[3] = 0x03  // LT high byte
    var packet = Data([0x20, 32, 0, 14])
    packet += payload
    let events = try parser.parse(data: packet)
    let ltEvent = events.first {
      if case .leftTriggerChanged = $0 { return true }
      return false
    }
    guard case .leftTriggerChanged(let ltVal) = ltEvent else {
      Issue.record("No leftTriggerChanged event")
      return
    }
    #expect(abs(ltVal - 1.0) < 0.01)
  }

  @Test func testStickNormalization() throws {
    let parser = GIPParser()
    var payload = Data(repeating: 0, count: 14)
    // LSX = Int16(-32768) = full left -> lx ~ -1.0
    payload[6] = 0x00
    payload[7] = 0x80
    // LSY = Int16(-32768) -> ly = -(-32768/32767) ~ +1.0
    payload[8] = 0x00
    payload[9] = 0x80
    var packet = Data([0x20, 32, 0, 14])
    packet += payload
    let events = try parser.parse(data: packet)
    let lsEvent = events.first {
      if case .leftStickChanged = $0 { return true }
      return false
    }
    guard case .leftStickChanged(let lx, let ly) = lsEvent else {
      Issue.record("No leftStickChanged event")
      return
    }
    #expect(abs(lx - (-1.0)) < 0.01)
    #expect(abs(ly - 1.0) < 0.01)
  }

  @Test func testDpadCombinations() throws {
    let parser = GIPParser()
    // up+right = 1+8 = 9
    var payload = Data(repeating: 0, count: 14)
    payload[1] = 9
    var packet = Data([0x20, 32, 0, 14])
    packet += payload
    let events = try parser.parse(data: packet)
    #expect(events.contains(.dpadChanged(.northEast)))
  }

  @Test func testUnhandledReportTypeReturnsEmpty() throws {
    let parser = GIPParser()
    let packet = Data([99, 32, 0, 2, 0, 0])
    let events = try parser.parse(data: packet)
    #expect(events.isEmpty)
  }

  @Test func testChangeDetectionSuppressesDuplicates() throws {
    let parser = GIPParser()
    var payload1 = Data(repeating: 0, count: 14)
    payload1[0] = 16  // A
    var packet1 = Data([0x20, 32, 0, 14])
    packet1 += payload1
    let events1 = try parser.parse(data: packet1)
    #expect(events1.contains(.buttonPressed(.a)))

    // Same state again - no button changes
    let events2 = try parser.parse(data: packet1)
    #expect(!events2.contains(.buttonPressed(.a)))
    #expect(!events2.contains(.buttonReleased(.a)))
  }

  @Test func testReleaseClearsHeldButtonAndDoesNotRepeatWhileNeutral() throws {
    let parser = GIPParser()
    var held = Data(repeating: 0, count: 14)
    held[1] = 1  // D-pad up
    var heldPacket = Data([0x20, 32, 0, 14])
    heldPacket += held
    let pressEvents = try parser.parse(data: heldPacket)
    #expect(pressEvents.contains(.dpadChanged(.north)))

    var neutralPacket = Data([0x20, 32, 1, 14])
    neutralPacket += Data(repeating: 0, count: 14)
    let releaseEvents = try parser.parse(data: neutralPacket)
    #expect(releaseEvents.contains(.dpadChanged(.neutral)))

    let repeatedNeutralEvents = try parser.parse(data: neutralPacket)
    #expect(repeatedNeutralEvents.isEmpty)
  }

  private func inputPacket(payload: Data) -> Data {
    Data([GIPCommand.input, 32, 0, UInt8(payload.count)]) + payload
  }

}
