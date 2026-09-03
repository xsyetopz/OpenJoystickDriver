import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

struct PacketLogCursorTests {
  @Test func ignoresTheSnapshotThatExistedWhenTracingStarted() throws {
    let existing = try entry(timestamp: 1, hex: "01")
    var cursor = PacketLogCursor(snapshot: [existing])

    #expect(cursor.consume(snapshot: [existing]).isEmpty)
  }

  @Test func returnsOnlyEntriesAppendedAfterThePreviousSnapshot() throws {
    let first = try entry(timestamp: 1, hex: "01")
    let second = try entry(timestamp: 2, hex: "02")
    let third = try entry(timestamp: 3, hex: "03")
    var cursor = PacketLogCursor(snapshot: [first])

    #expect(cursor.consume(snapshot: [first, second]).map(\.hex) == ["02"])
    #expect(cursor.consume(snapshot: [first, second, third]).map(\.hex) == ["03"])
  }

  @Test func followsEntriesWhenTheRingDropsItsOldestValue() throws {
    let first = try entry(timestamp: 1, hex: "01")
    let second = try entry(timestamp: 2, hex: "02")
    let third = try entry(timestamp: 3, hex: "03")
    var cursor = PacketLogCursor(snapshot: [first, second])

    #expect(cursor.consume(snapshot: [second, third]).map(\.hex) == ["03"])
  }

  @Test func treatsSamePayloadAtDifferentTimesAsNewPackets() throws {
    let first = try entry(timestamp: 1, hex: "AA")
    let second = try entry(timestamp: 2, hex: "AA")
    var cursor = PacketLogCursor(snapshot: [first])

    #expect(cursor.consume(snapshot: [first, second]).map(\.timestamp) == [2])
  }

  private func entry(timestamp: TimeInterval, hex: String) throws -> PacketLogEntry {
    let data = try JSONSerialization.data(withJSONObject: [
      "timestamp": timestamp, "direction": "rx", "hex": hex, "length": 1
    ])
    return try JSONDecoder().decode(PacketLogEntry.self, from: data)
  }
}
