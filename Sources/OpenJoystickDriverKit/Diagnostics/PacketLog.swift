public import Foundation

/// Transfer direction of a logged packet; raw values are the packet-log wire strings.
public enum PacketLogDirection: String, Codable, Sendable {
  /// Incoming from the controller.
  case received = "Rx"
  /// Outgoing to the controller.
  case transmitted = "Tx"
}

/// Whether a packet is controller traffic or routine upkeep.
public enum PacketLogClassification: Sendable, Equatable {
  /// A packet that carries input or output.
  case activity
  /// A GIP announce or status command.
  case gipHousekeeping
}

/// One recorded USB packet shown in the Developer tab packet log.
///
/// Stored in a ring buffer inside ``DevicePipeline`` (up to 200 entries).
public struct PacketLogEntry: Codable, Sendable {
  /// Seconds since reference date when the packet was captured.
  public let timestamp: TimeInterval
  /// Transfer direction of the packet.
  public let direction: PacketLogDirection
  /// Packet payload as a hex-encoded string (e.g. `"05 20 00 01 00"`).
  public let hex: String
  /// Number of bytes in the packet.
  public let length: Int

  /// The packet's bytes, from its `hex` string.
  public var reportBytes: [UInt8] { Self.bytes(hex: hex) }

  /// The bytes of a space-separated hex string; a group that is not hex is skipped.
  public static func bytes(hex: String) -> [UInt8] {
    hex.split(separator: " ").compactMap { UInt8($0, radix: 16) }
  }

  /// Classifies demonstrated GIP announce and status commands as routine housekeeping.
  public var classification: PacketLogClassification {
    var command: UInt8 = 0
    var digits = 0
    for byte in hex.utf8 {
      if byte == 0x20 || byte == 0x09 { break }
      let digit: UInt8
      switch byte {
      case 48...57: digit = byte - 48
      case 65...70: digit = byte - 55
      case 97...102: digit = byte - 87
      default: return .activity
      }
      guard digits < 2 else { return .activity }
      command = command << 4 | digit
      digits += 1
    }
    guard digits == 2 else { return .activity }
    return command == 0x02 || command == 0x03 ? .gipHousekeeping : .activity
  }
}

/// Tracks newly appended entries across snapshots of a bounded packet ring.
public struct PacketLogSnapshotCursor: Sendable {
  /// The entries of the snapshot that `consume(snapshot:)` last saw.
  private var previous: [PacketLogEntry]

  /// Creates a cursor that treats `snapshot` as already seen.
  public init(snapshot: [PacketLogEntry] = []) { previous = snapshot }

  /// The entries of `snapshot` that are new since the last snapshot.
  ///
  /// It finds the longest run at the start of `snapshot` that ends the previous snapshot, because
  /// the ring drops its oldest entries as it fills.
  public mutating func consume(snapshot: [PacketLogEntry]) -> [PacketLogEntry] {
    let overlap = Self.overlap(previous: previous, snapshot: snapshot)
    previous = snapshot
    return Array(snapshot.dropFirst(overlap))
  }

  /// Whether the two entries have the same timestamp, direction, length and hex text.
  private static func matches(_ pair: (PacketLogEntry, PacketLogEntry)) -> Bool {
    pair.0.timestamp == pair.1.timestamp && pair.0.direction == pair.1.direction
      && pair.0.length == pair.1.length && pair.0.hex == pair.1.hex
  }

  /// The number of entries at the start of `snapshot` that repeat the end of `previous`.
  private static func overlap(previous: [PacketLogEntry], snapshot: [PacketLogEntry]) -> Int {
    var sequence = snapshot.map(Optional.some)
    sequence.append(nil)
    sequence.append(contentsOf: previous.map(Optional.some))
    guard !sequence.isEmpty else { return 0 }
    var prefix = Array(repeating: 0, count: sequence.count)
    for index in 1..<sequence.count {
      var candidate = prefix[index - 1]
      while candidate > 0, !matches(sequence[candidate], sequence[index]) {
        candidate = prefix[candidate - 1]
      }
      if matches(sequence[candidate], sequence[index]) { candidate += 1 }
      prefix[index] = candidate
    }
    return min(prefix[sequence.count - 1], snapshot.count)
  }

  /// Whether the two optional entries match; two nil values match, which marks the join of the two
  /// sequences.
  private static func matches(_ lhs: PacketLogEntry?, _ rhs: PacketLogEntry?) -> Bool {
    switch (lhs, rhs) {
    case (.some(let lhs), .some(let rhs)): return matches((lhs, rhs))
    case (.none, .none): return true
    default: return false
    }
  }
}
