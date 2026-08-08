import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct PacketLogBufferTests {
  @Test func materializesTheExistingPacketLogContractOnRead() {
    let buffer = PacketLogBuffer(maxEntries: 3)
    buffer.append(bytes: [0x00, 0x0A, 0xFF], direction: "rx", timestamp: 10)
    buffer.append(bytes: [], direction: "tx", timestamp: 11)

    let entries = buffer.entries()
    #expect(entries.count == 2)
    #expect(entries[0].timestamp == 10)
    #expect(entries[0].direction == "rx")
    #expect(entries[0].length == 3)
    #expect(entries[0].hex == "00 0A FF")
    #expect(entries[1].timestamp == 11)
    #expect(entries[1].direction == "tx")
    #expect(entries[1].length == 0)
    #expect(entries[1].hex.isEmpty)
  }

  @Test func keepsOnlyTheNewestBoundedEntries() {
    let buffer = PacketLogBuffer(maxEntries: 2)
    buffer.append(bytes: [1], direction: "rx", timestamp: 1)
    buffer.append(bytes: [2], direction: "rx", timestamp: 2)
    buffer.append(bytes: [3], direction: "rx", timestamp: 3)

    let entries = buffer.entries()
    #expect(entries.map(\.timestamp) == [2, 3])
    #expect(entries.map(\.hex) == ["02", "03"])
  }

  @Test func concurrentInputNeverExceedsTheRingLimit() {
    let buffer = PacketLogBuffer(maxEntries: 200)
    DispatchQueue.concurrentPerform(iterations: 1_000) { value in
      buffer.append(
        bytes: [UInt8(truncatingIfNeeded: value)],
        direction: "rx",
        timestamp: TimeInterval(value)
      )
    }

    #expect(buffer.entries().count == 200)
  }
}
