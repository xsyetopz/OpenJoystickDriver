import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct PacketLogStreamTests {
  private func entry(_ time: TimeInterval, _ hex: String) throws -> PacketLogEntry {
    let json = """
      {"timestamp": \(time), "direction": "Rx", "hex": "\(hex)", "length": 1}
      """
    return try JSONDecoder().decode(PacketLogEntry.self, from: Data(json.utf8))
  }

  @Test
  func deliversEachReportAfterTheFirstSnapshotOnce() async throws {
    let snapshots = [
      [try entry(1, "01")], [try entry(1, "01"), try entry(2, "02")],
      [try entry(1, "01"), try entry(2, "02")], [try entry(2, "02"), try entry(3, "03")],
    ]
    let calls = Locked(0)
    var seen: [String] = []
    try await PacketLogStream.follow(duration: 0.05, interval: 1_000_000) {
      let index = calls.withLock { call in
        defer { call += 1 }
        return min(call, snapshots.count - 1)
      }
      return snapshots[index]
    } onEntry: {
      seen.append($0.hex)
    }
    #expect(seen == ["02", "03"])
  }
}
