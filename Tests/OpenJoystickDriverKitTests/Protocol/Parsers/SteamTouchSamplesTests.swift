import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct SteamTouchSamplesTests {
  private func packet(counter: UInt8, flags: UInt8, x: Int16, y: Int16) -> Data {
    var bytes = [UInt8](repeating: 0, count: 64)
    bytes[0] = 1
    bytes[2] = 1
    bytes[3] = 60
    bytes[4] = counter
    bytes[10] = flags
    for (offset, value) in [(16, x), (18, y), (20, Int16(-123)), (22, Int16(456))] {
      bytes[offset] = UInt8(truncatingIfNeeded: value)
      bytes[offset + 1] = UInt8(truncatingIfNeeded: UInt16(bitPattern: value) >> 8)
    }
    return Data(bytes)
  }

  private func touches(_ events: [ControllerEvent]) -> [ControllerTouchSample] {
    events.compactMap {
      if case .touchSample(let sample) = $0 { return sample }
      return nil
    }
  }

  @Test func independentPadsPreserveSignedCoordinatesAndReleaseFrames() throws {
    let parser = SteamControllerParser()
    let events = try parser.parse(data: packet(counter: 1, flags: 0x18, x: -32_768, y: 32_767))
    let frames = touches(events)
    try #require(frames.count == 2)
    #expect(frames.map(\.surface) == [.left, .right])
    #expect(frames.allSatisfy { $0.originX == -32_768 && $0.width == 65_536 })
    #expect(
      frames[0].contacts == [ControllerTouchContact(id: 0, isActive: true, x: -32_768, y: 32_767)]
    )
    #expect(frames[1].contacts == [ControllerTouchContact(id: 0, isActive: true, x: -123, y: 456)])
    let decoded = try JSONDecoder().decode(
      [ControllerTouchSample].self,
      from: JSONEncoder().encode(frames)
    )
    #expect(decoded == frames)
    let released = touches(try parser.parse(data: packet(counter: 2, flags: 0, x: 0, y: 0)))
    #expect(released.count == 2)
    #expect(released.allSatisfy { !$0.contacts[0].isActive })
  }

  @Test func interleavedPadAndStickPacketsDoNotOverwriteEachOther() throws {
    let parser = SteamControllerParser()
    _ = try parser.parse(data: packet(counter: 1, flags: 0, x: 16_384, y: 0))
    let pad = try parser.parse(data: packet(counter: 2, flags: 0x88, x: -12_000, y: 8000))
    #expect(!pad.contains { if case .leftStickChanged = $0 { return true }; return false })
    let stick = try parser.parse(data: packet(counter: 3, flags: 0x80, x: 20_000, y: 0))
    let left = try #require(touches(stick).first)
    #expect(left.contacts[0].isActive)
    #expect(left.contacts[0].x == -12_000 && left.contacts[0].y == 8000)
    #expect(stick.contains { if case .leftStickChanged = $0 { return true }; return false })
    let padOnly = try parser.parse(data: packet(counter: 4, flags: 8, x: 100, y: 200))
    #expect(padOnly.contains(.leftStickChanged(x: 0, y: 0)))
  }
}
