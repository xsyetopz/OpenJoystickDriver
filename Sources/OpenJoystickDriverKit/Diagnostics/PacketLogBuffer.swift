import Foundation

/// Bounded raw packet ring that defers expensive hexadecimal formatting until read.
///
/// The input path stores only timestamp, direction, and raw bytes. This avoids
/// formatting and duplicating packet strings for controllers that may report
/// hundreds of times per second while no diagnostic consumer is visible.
final class PacketLogBuffer: @unchecked Sendable {
  private struct BufferedPacket: Sendable {
    let timestamp: TimeInterval
    let direction: String
    let bytes: [UInt8]
  }

  // The lock guards the bounded raw entry array. Formatting uses a copied snapshot.
  private let lock = NSLock()
  private let maxEntries: Int
  private var bufferedPackets: [BufferedPacket?]
  private var nextWriteIndex = 0
  private var entryCount = 0

  init(maxEntries: Int) {
    self.maxEntries = max(0, maxEntries)
    self.bufferedPackets = Array(repeating: nil, count: self.maxEntries)
  }

  func append(
    bytes: [UInt8],
    direction: String,
    timestamp: TimeInterval = Date().timeIntervalSince1970
  ) {
    guard maxEntries > 0 else { return }
    let entry = BufferedPacket(timestamp: timestamp, direction: direction, bytes: bytes)
    lock.withLock {
      bufferedPackets[nextWriteIndex] = entry
      nextWriteIndex = (nextWriteIndex + 1) % maxEntries
      entryCount = min(entryCount + 1, maxEntries)
    }
  }

  func entries() -> [PacketLogEntry] {
    let snapshot: [BufferedPacket] = lock.withLock {
      guard entryCount > 0 else { return [] }
      let oldestIndex = entryCount == maxEntries ? nextWriteIndex : 0
      return (0..<entryCount).compactMap {
        bufferedPackets[(oldestIndex + $0) % maxEntries]
      }
    }
    return snapshot.map {
      PacketLogEntry(
        timestamp: $0.timestamp,
        direction: $0.direction,
        hex: Self.hexString(for: $0.bytes),
        length: $0.bytes.count
      )
    }
  }

  private static func hexString(for bytes: [UInt8]) -> String {
    guard !bytes.isEmpty else { return "" }

    let digits = Array("0123456789ABCDEF".utf8)
    var output: [UInt8] = []
    output.reserveCapacity(bytes.count * 3 - 1)
    for (index, byte) in bytes.enumerated() {
      if index > 0 { output.append(0x20) }
      output.append(digits[Int(byte >> 4)])
      output.append(digits[Int(byte & 0x0F)])
    }
    return String(bytes: output, encoding: .utf8) ?? ""
  }
}
