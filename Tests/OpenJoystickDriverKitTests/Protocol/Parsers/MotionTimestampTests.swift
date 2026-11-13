import Foundation
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

/// Motion sample time shares the `ControllerEvent.timestamp` monotonic domain: each parser session
/// anchors at its first sample's receipt time, and sensor time only adds deltas after it.
struct MotionTimestampTests {
  /// A 64-byte DualSense USB report at `counter` (1000/3 ns ticks), lying face up at rest.
  private func dualSenseReport(counter: UInt32) -> Data {
    var report = [UInt8](repeating: 0, count: 64)
    report[0] = 1
    report[8] = 8
    // Raw accel Y 8192 is +1 g on canonical Z.
    report[24] = 0x00
    report[25] = 0x20
    for byte in 0..<4 { report[28 + byte] = UInt8(truncatingIfNeeded: counter >> (8 * byte)) }
    return Data(report)
  }

  @Test
  func dualSenseResetReanchorsAtReceiptKeepsDeltasAndFeedsEngine() throws {
    let parser = DualSenseDriver()
    var engine = RemappingMotionProcessor()
    var samples: [ControllerMotionSample] = []
    // Receipt jitter does not move device-counter time within one session.
    for (counter, receipt) in [(100, 5_000_000_000), (130, 5_000_900_000), (160, 5_025_000_000)] {
      let event = try #require(
        try parser.parseReport(dualSenseReport(counter: UInt32(counter)), at: UInt64(receipt))
      )
      let sample = try #require(event.motion.first)
      if samples.isEmpty { #expect(sample.timestamp.monotonic == event.timestamp) }
      samples.append(sample)
      engine.process(sample)
    }
    // 30 ticks of 1000/3 ns each.
    #expect(
      samples.map(\.timestamp.monotonic.nanoseconds) == [
        5_000_000_000, 5_000_010_000, 5_000_020_000,
      ]
    )
    #expect(engine.latest?.deltaTime == 0.000_01)

    parser.resetProtocolState()
    var resumed: [ControllerMotionSample] = []
    for (counter, receipt) in [(7, 9_000_000_000), (37, 9_004_000_000)] {
      let event = try #require(
        try parser.parseReport(dualSenseReport(counter: UInt32(counter)), at: UInt64(receipt))
      )
      let sample = try #require(event.motion.first)
      if resumed.isEmpty { #expect(sample.timestamp.monotonic == event.timestamp) }
      resumed.append(sample)
      engine.process(sample)
    }
    #expect(resumed.map(\.timestamp.monotonic.nanoseconds) == [9_000_000_000, 9_000_010_000])
    #expect(resumed.map(\.timestamp.sequenceIndex) == [3, 4])
    #expect(engine.latest?.timestamp == resumed.last?.timestamp)
    #expect(engine.latest?.deltaTime == 0.000_01)
  }

  @Test
  func separateNintendoSessionsShareEventTimeDomain() throws {
    var report = [UInt8](repeating: 0, count: 49)
    report[0] = 0x30
    let early = Switch1Driver()
    let late = Switch1Driver()
    let lateEvent = try #require(try late.parseReport(Data(report), at: 2_000_000_000))
    let earlyEvent = try #require(try early.parseReport(Data(report), at: 1_000_000_000))
    // The oldest sample of each first report is dated at its receipt; the newest 10 ms later.
    #expect(earlyEvent.motion.first?.timestamp.monotonic == earlyEvent.timestamp)
    #expect(lateEvent.motion.first?.timestamp.monotonic == lateEvent.timestamp)
    let earlyTimes = earlyEvent.motion.map(\.timestamp.monotonic.nanoseconds)
    #expect(earlyTimes == [1_000_000_000, 1_005_000_000, 1_010_000_000])
    #expect(try #require(earlyEvent.motion.last).timestamp.monotonic < lateEvent.timestamp)

    let next = try #require(try early.parseReport(Data(report), at: 1_015_000_000))
    #expect(
      next.motion.map(\.timestamp.monotonic.nanoseconds)
        == [1_015, 1_020, 1_025].map { $0 * 1_000_000 }
    )
    early.resetProtocolState()
    let reset = try #require(try early.parseReport(Data(report), at: 3_000_000_000))
    #expect(reset.motion.first?.timestamp.monotonic == reset.timestamp)
    #expect(reset.motion.map(\.timestamp.sequenceIndex) == [6, 7, 8])
  }

  @Test
  func steamResetReanchorsAtReceipt() throws {
    let parser = SteamControllerDriver()
    var report = Array(ProtocolPacketFixtures.Steam.inputReport())
    let first = try #require(try parser.parseReport(Data(report), at: 4_000_000_000))
    #expect(first.motion.first?.timestamp.monotonic == first.timestamp)
    report[4] &+= 1
    let second = try #require(try parser.parseReport(Data(report), at: 4_004_000_000))
    #expect(second.motion.first?.timestamp.monotonic == second.timestamp)
    parser.resetProtocolState()
    // Duplicate tracking also restarts, so the same sequence number is a new sample.
    let resumed = try #require(try parser.parseReport(Data(report), at: 6_000_000_000))
    let sample = try #require(resumed.motion.first)
    #expect(sample.timestamp.monotonic == resumed.timestamp)
    #expect(sample.timestamp.sequenceIndex == 2)
  }
}
