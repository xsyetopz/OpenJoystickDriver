import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct PacketLogBufferTests {
  @Test
  func directionRawValuesAreWireStrings() {
    #expect(PacketLogDirection.received.rawValue == "Rx")
    #expect(PacketLogDirection.transmitted.rawValue == "Tx")
  }

  @Test
  func classifiesGIPAnnounceAndStatusAsHousekeepingInEitherDirection() {
    let buffer = armedBuffer(maxEntries: 4)
    buffer.append(bytes: [0x02, 0x20], direction: .received, timestamp: 1)
    buffer.append(bytes: [0x03, 0x20], direction: .transmitted, timestamp: 2)
    buffer.append(bytes: [0x20, 0x00], direction: .received, timestamp: 3)
    buffer.append(bytes: [], direction: .transmitted, timestamp: 4)

    #expect(
      buffer.entries().map(\.classification) == [
        .gipHousekeeping, .gipHousekeeping, .activity, .activity,
      ]
    )
  }

  @Test
  func materializesExistingPacketLogContractOnRead() {
    let buffer = armedBuffer(maxEntries: 3)
    buffer.append(bytes: [0x00, 0x0A, 0xFF], direction: .received, timestamp: 10)
    buffer.append(bytes: [], direction: .transmitted, timestamp: 11)

    let entries = buffer.entries()
    #expect(entries.count == 2)
    #expect(entries[0].timestamp == 10)
    #expect(entries[0].direction == .received)
    #expect(entries[0].length == 3)
    #expect(entries[0].hex == "00 0A FF")
    #expect(entries[1].timestamp == 11)
    #expect(entries[1].direction == .transmitted)
    #expect(entries[1].length == 0)
    #expect(entries[1].hex.isEmpty)
  }

  @Test
  func keepsOnlyNewestBoundedEntries() {
    let buffer = armedBuffer(maxEntries: 2)
    buffer.append(bytes: [1], direction: .received, timestamp: 1)
    buffer.append(bytes: [2], direction: .received, timestamp: 2)
    buffer.append(bytes: [3], direction: .received, timestamp: 3)

    let entries = buffer.entries()
    #expect(entries.map(\.timestamp) == [2, 3])
    #expect(entries.map(\.hex) == ["02", "03"])
  }

  @Test
  func concurrentInputNeverExceedsRingLimit() {
    let buffer = armedBuffer(maxEntries: 200)
    DispatchQueue.concurrentPerform(iterations: 1_000) { value in
      buffer.append(
        bytes: [UInt8(truncatingIfNeeded: value)],
        direction: .received,
        timestamp: TimeInterval(value)
      )
    }

    #expect(buffer.entries().count == 200)
  }

  @Test
  func recordsNothingUntilDiagnosticReaderArmsCapture() {
    let buffer = PacketLogBuffer(maxEntries: 4) { 1 }
    buffer.append(bytes: [0x01], direction: .received, timestamp: 1)
    #expect(buffer.entries().isEmpty)

    buffer.armCapture()
    buffer.append(bytes: [0x02], direction: .received, timestamp: 2)
    #expect(buffer.entries().map(\.hex) == ["02"])
  }

  @Test
  func lapsedLeaseStopsCaptureAndDiscardsWhatWasCaptured() {
    let clock = PacketLogClock()
    let buffer = PacketLogBuffer(maxEntries: 4, captureLeaseNanoseconds: 10) { clock.now }
    buffer.armCapture()
    buffer.append(bytes: [0x01], direction: .received, timestamp: 1)
    clock.now = 5
    buffer.armCapture()  // Renewing within the lease keeps the ring.
    buffer.append(bytes: [0x02], direction: .received, timestamp: 2)
    #expect(buffer.entries().map(\.hex) == ["01", "02"])

    clock.now = 15
    buffer.append(bytes: [0x03], direction: .received, timestamp: 3)
    #expect(buffer.entries().isEmpty)

    buffer.append(bytes: [0x04], direction: .received, timestamp: 4)
    buffer.armCapture()
    #expect(buffer.entries().isEmpty)
  }

  @Test
  func rearmingAfterLapseStartsFromEmptyRingWithoutInterveningPacket() {
    let clock = PacketLogClock()
    let buffer = PacketLogBuffer(maxEntries: 4, captureLeaseNanoseconds: 10) { clock.now }
    buffer.armCapture()
    buffer.append(bytes: [0x01], direction: .received, timestamp: 1)
    clock.now = 20
    buffer.armCapture()
    #expect(buffer.entries().isEmpty)
  }

  @Test
  func expiryCheckDiscardsCapturedPacketsOnlyAfterLeaseLapses() {
    let clock = PacketLogClock()
    let buffer = PacketLogBuffer(maxEntries: 4, captureLeaseNanoseconds: 10) { clock.now }
    buffer.armCapture()
    buffer.append(bytes: [0x01], direction: .received, timestamp: 1)

    clock.now = 9
    buffer.expireIfLapsed()
    #expect(buffer.entries().map(\.hex) == ["01"])

    clock.now = 10
    buffer.expireIfLapsed()
    #expect(buffer.entries().isEmpty)
  }

  private func armedBuffer(maxEntries: Int) -> PacketLogBuffer {
    let buffer = PacketLogBuffer(maxEntries: maxEntries) { 0 }
    buffer.armCapture()
    return buffer
  }
}

private final class PacketLogClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value: UInt64 = 0
  var now: UInt64 {
    get { lock.withLock { value } }
    set { lock.withLock { value = newValue } }
  }
}
