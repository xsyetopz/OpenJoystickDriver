import Foundation
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

extension GIPDriverTests {
  @Test
  func testGamesirStyleThirtyTwoByteGIPReportMapsViewGuideMenuAndShareFromPacketBytes() throws {
    let parser = GIPDriver(shareButtonFromEnd: 18)
    let view = try parser.parseReport(
      Data([

        0x20, 0x00, 0x03, 0x20, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      ])
    )
    #expect(view.contains(.press(.back)))

    #expect(!view.contains(.press(.capture)))
    #expect(!view.contains(.press(.start)))

    _ = try parser.parseReport(
      Data([

        0x20, 0x00, 0x04, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      ])
    )

    let guidePress = try parser.parseReport(Data([0x07, 0x20, 0x00, 0x02, 0x01, 0x5B]))

    #expect(guidePress.contains(.press(.guide)))
    let guideRelease = try parser.parseReport(Data([0x07, 0x20, 0x01, 0x02, 0x00, 0x5B]))
    #expect(guideRelease.contains(.release(.guide)))

    let menu = try parser.parseReport(
      Data([

        0x20, 0x00, 0x05, 0x20, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      ])
    )
    #expect(menu.contains(.press(.start)))

    #expect(!menu.contains(.press(.capture)))

    _ = try parser.parseReport(
      Data([

        0x20, 0x00, 0x06, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      ])
    )

    let share = try parser.parseReport(

      Data([
        // Live GameSir G7 SE Share press: payload[14] = 0x01 on a 32-byte GIP input.
        0x20, 0x00, 0x47, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      ])
    )
    #expect(share.contains(.press(.capture)))
    #expect(!share.contains(.press(.back)))
    #expect(!share.contains(.press(.start)))

    let shareRelease = try parser.parseReport(
      Data([
        0x20, 0x00, 0x48, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      ])
    )
    #expect(shareRelease.contains(.release(.capture)))
  }

  /// Linux xpad reads `data[len - 26]` of the whole packet; SDL reads payload byte 18 of the
  /// 44-byte Series X firmware 5.5 payload and byte 14 of the 40-byte firmware 5.1 payload.
  @Test
  func testShareOffsetReadsShareFromTheEndRelativeGIPPacking() throws {
    for (count, shareIndex) in [(44, 18), (40, 14)] {
      let parser = GIPDriver(shareButtonFromEnd: 26)
      var payload = Data(repeating: 0, count: count)
      payload[shareIndex] = 1
      let events = try parser.parseReport(ProtocolPacketFixtures.GIP.inputPacket(payload: payload))
      #expect(events.contains(.press(.capture)), "payload \(count)")
    }
  }

  /// A pad whose record names no Share offset has no Share, so byte 14 of its input is not read
  /// as one.
  @Test
  func testUndeclaredShareIsNotDecoded() throws {
    let parser = GIPDriver()
    var payload = Data(repeating: 0, count: 32)
    payload[14] = 1
    let events = try parser.parseReport(ProtocolPacketFixtures.GIP.inputPacket(payload: payload))
    #expect(!events.contains(.press(.capture)))
    #expect(!parser.capabilities.controls.contains(.capture))
  }

  @Test
  func testFirmwareCommandDoesNotInventExtraButtons() throws {
    let parser = GIPDriver()
    var payload = Data(repeating: 0, count: 16)
    payload[14] = 0x05
    let packet = Data([0x0C, 32, 0, UInt8(payload.count)]) + payload
    #expect(try parser.parseReport(packet) == nil)
  }

  // Razer Wolverine TE 1532:0A15 announce captured on hardware (2026-09-26).
  private static func announce(sequence: UInt8) -> Data {
    Data([0x02, 0x20, sequence, 0x1C, 0x59, 0xE9, 0x51, 0x77, 0xCF, 0x39, 0x00, 0x00])
      + Data([0x32, 0x15, 0x15, 0x0A, 0x01, 0x00, 0x01, 0x00, 0x40, 0x01, 0x02, 0x00])
      + Data([0x01, 0x00, 0x01, 0x00, 0x01, 0x00, 0x01, 0x00])
  }

  @Test
  func announceBeforeFirstInputResendsTheStartupSequenceBounded() throws {
    let parser = GIPDriver()
    let startupCommands = parser.startupWrites().usbBytes.map(\.first)
    let limit = PhysicalProtocolID.xboxGIP.described(limit: \.announceResendLimit)
    var resends = 0
    for sequence in 0..<UInt8(64) {
      #expect(try parser.parseReport(Self.announce(sequence: sequence)) == nil)
      let output = parser.drainPendingWrites().usbBytes
      if sequence.isMultiple(of: 4), Int(sequence) < 4 * limit {
        #expect(output.map(\.first) == startupCommands)
        resends += 1
      } else {
        #expect(output.isEmpty)
      }
    }
    #expect(resends == limit)
  }

  @Test
  func resetStartsANewSessionForReconnect() throws {
    let parser = GIPDriver()
    let firstAttachStartup = GIPDriver().startupWrites().usbBytes
    _ = parser.startupWrites()
    _ = try parser.parseReport(Data([0x20, 0x00, 0x01, 0x0E] + [UInt8](repeating: 0, count: 14)))
    _ = try parser.parseReport(Self.announce(sequence: 1))
    // A partial frame from the old session, and an acknowledgement it still owes.
    _ = try parser.parseReport(
      Data([GIPCommand.virtualKey, GIPOption.acknowledge, 0x55, 2, 1, 0x5B])
    )
    _ = try parser.parseReport(Data([0x20, 0x00, 0x02, 0x0E]))

    parser.resetProtocolState()

    #expect(parser.drainPendingWrites().isEmpty)
    #expect(parser.startupWrites().usbBytes == firstAttachStartup)
    #expect(try parser.parseReport(Self.announce(sequence: 0)) == nil)
    #expect(parser.drainPendingWrites().usbBytes.map(\.first) == firstAttachStartup.map(\.first))
  }

  @Test
  func announceAfterInputDoesNotResendTheStartupSequence() throws {
    let parser = GIPDriver()
    _ = try parser.parseReport(Data([0x20, 0x00, 0x01, 0x0E] + [UInt8](repeating: 0, count: 14)))
    _ = parser.drainPendingWrites()
    _ = try parser.parseReport(Self.announce(sequence: 2))
    #expect(parser.drainPendingWrites().isEmpty)
  }

}

extension GIPDriverTests {
  private static let neutralMainReport = Data(
    [0x20, 0x00, 0x09, 0x20] + [UInt8](repeating: 0, count: 32)
  )

  @Test
  func sessionResetForgetsAGuideHeldOnlyByVirtualKeyFrames() throws {
    let parser = GIPDriver()
    #expect(
      try parser.parseReport(Data([0x07, 0x20, 0x00, 0x02, 0x01, 0x5B])).contains(.press(.guide))
    )

    parser.resetProtocolState()

    let first = try parser.parseReport(Self.neutralMainReport)
    #expect(first?.state == .neutral)
  }

  @Test
  func overlongHeaderVarintIsDiscardedSoTheNextTransferParses() throws {
    let parser = GIPDriver()
    #expect(throws: GIPError.self) {
      try parser.parseReport(Data([0x20, 0x00, 0x01, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80]))
    }

    let next = try parser.parseReport(Self.neutralMainReport)
    #expect(next?.state == .neutral)
  }
}
