import Foundation

/// One recorded USB packet shown in the Developer tab packet log.
///
/// Stored in a ring buffer inside ``DevicePipeline`` (up to 200 entries).
public struct PacketLogEntry: Codable, Sendable {
  /// Seconds since reference date when the packet was captured.
  public let timestamp: TimeInterval
  /// Transfer direction: `"rx"` for incoming, `"tx"` for outgoing.
  public let direction: String
  /// Packet payload as a hex-encoded string (e.g. `"05 20 00 01 00"`).
  public let hex: String
  /// Number of bytes in the packet.
  public let length: Int
}

/// Tracks newly appended entries across snapshots of a bounded packet ring.
public struct PacketLogSnapshotCursor: Sendable {
  private var previous: [PacketLogEntry]

  public init(snapshot: [PacketLogEntry] = []) { previous = snapshot }

  public mutating func consume(snapshot: [PacketLogEntry]) -> [PacketLogEntry] {
    let maximumOverlap = min(previous.count, snapshot.count)
    let overlap =
      stride(from: maximumOverlap, through: 0, by: -1).first { count in
        count == 0 || zip(previous.suffix(count), snapshot.prefix(count)).allSatisfy(Self.matches)
      } ?? 0
    previous = snapshot
    return Array(snapshot.dropFirst(overlap))
  }

  private static func matches(_ pair: (PacketLogEntry, PacketLogEntry)) -> Bool {
    pair.0.timestamp == pair.1.timestamp && pair.0.direction == pair.1.direction
      && pair.0.length == pair.1.length && pair.0.hex == pair.1.hex
  }
}
