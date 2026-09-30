import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Report-`0x03` segments and chunked state packets in the layout of SDL `SDL_hidapi_steam.c`
/// (`WriteSegmentToSteamControllerPacketAssembler`, `UpdateBLESteamControllerState`). They come
/// from the source, not from a hardware capture.
private enum BLEReport {
  /// One 20-byte segment: report ID, header, and up to 18 payload bytes.
  static func segment(_ payload: [UInt8], number: UInt8 = 0, last: Bool = true) -> Data {
    var bytes = [UInt8](repeating: 0, count: 20)
    bytes[0] = 0x03
    bytes[1] = 0x80 | number | (last ? 0x40 : 0)
    bytes.replaceSubrange(2..<(2 + payload.count), with: payload)
    return Data(bytes)
  }

  /// A chunked state packet: type 4 and the chunk mask, then each present chunk in mask order.
  static func chunked(mask: UInt16, _ chunks: [UInt8]...) -> [UInt8] {
    [UInt8(truncatingIfNeeded: mask) | 0x04, UInt8(truncatingIfNeeded: mask >> 8)]
      + chunks.flatMap { $0 }
  }
}

@Suite
struct SteamControllerBluetoothTests {

  @Test
  func chunkedPacketsFillTheWiredStateAndKeepUnsentChunks() throws {
    let driver = SteamControllerDriver(isBluetooth: true)
    // Buttons chunk 1 (faceSouth), triggers, left stick.
    let first = BLEReport.chunked(mask: 0x00B0, [0x80, 0, 0], [255, 0], [0xFF, 0x7F, 0, 0])
    let event = try #require(try driver.parseReport(BLEReport.segment(first)))
    #expect(event.state.pressed == [.faceSouth])
    #expect(event.state.leftTrigger == .max)
    #expect(event.state.leftStick == StickPosition(x: 1, yDown: 0))

    // A triggers-only packet keeps the buttons and stick from the previous packet.
    let second = BLEReport.chunked(mask: 0x0020, [0, 255])
    let next = try #require(try driver.parseReport(BLEReport.segment(second)))
    #expect(next.state.pressed == [.faceSouth])
    #expect(next.state.leftTrigger == .min && next.state.rightTrigger == .max)
    #expect(next.state.leftStick == StickPosition(x: 1, yDown: 0))
  }

  @Test
  func assemblerJoinsSegmentsAndDropsBrokenSequences() throws {
    var assembler = SteamBluetoothAssembler()
    let head = [UInt8](repeating: 1, count: 18)
    let tail: [UInt8] = [2, 2]
    #expect(assembler.append(Array(BLEReport.segment(head, last: false))) == nil)
    let packet = assembler.append(Array(BLEReport.segment(tail, number: 1)))
    #expect(packet == head + tail + [UInt8](repeating: 0, count: 16))

    // A segment out of order resets the assembler; a first segment restarts it.
    #expect(assembler.append(Array(BLEReport.segment(tail, number: 1))) == nil)
    #expect(assembler.append(Array(BLEReport.segment(head, last: false))) == nil)
    #expect(assembler.append(Array(BLEReport.segment(tail, number: 2))) == nil)
    // A short segment, another report ID, or an empty segment yields no packet.
    #expect(assembler.append([0x03, 0xC0, 1]) == nil)
    #expect(assembler.append([0x01] + [UInt8](repeating: 0, count: 19)) == nil)
    #expect(assembler.append([0x03] + [UInt8](repeating: 0, count: 19)) == nil)
  }

  @Test
  func featureCommandsTravelAsReportThreeSegments() {
    let startup = SteamControllerDriver(isBluetooth: true).activationWrites().hidFeatures
    #expect(startup.map(\.reportID) == [3, 3])
    #expect(startup.map(\.bytes.count) == [20, 20])
    #expect(Array(startup[0].bytes.prefix(3)) == [0x03, 0xC0, 0x81])
    // Lizard-mode settings plus SETTING_WIRELESS_PACKET_VERSION 2.
    #expect(
      Array(startup[1].bytes.prefix(16)) == [
        0x03, 0xC0, 0x87, 12, 7, 7, 0, 8, 7, 0, 48, 0x18, 0, 49, 2, 0,
      ]
    )

    let long = SteamBluetooth.featureReports(Array(0..<20))
    #expect(long.map { $0.bytes[1] } == [0x80, 0xC1])
    #expect(Array(long[1].bytes.prefix(4)) == [0x03, 0xC1, 18, 19])
  }
}
