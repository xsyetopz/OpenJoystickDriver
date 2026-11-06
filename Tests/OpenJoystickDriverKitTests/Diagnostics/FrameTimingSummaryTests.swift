import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct FrameTimingSummaryTests {
  /// A window of 101 frames with fixed stage delays.
  ///
  /// Read intervals are 1 ms except 2 ms before frame 40 and 10 ms before frame 70. Parse follows
  /// read by 10, 20, 30 or 40 microseconds in turn, dispatch follows parse by 5 microseconds, even
  /// frames reach the virtual device 50 microseconds after dispatch, and only the last frame
  /// reaches the endpoint, 700 microseconds after dispatch.
  private static func window() -> [FrameTiming] {
    var read: UInt64 = 1_000
    return (0..<101).map { index in
      if index > 0 { read += index == 40 ? 2_000_000 : index == 70 ? 10_000_000 : 1_000_000 }
      let parse = read + UInt64(index % 4 + 1) * 10_000
      let dispatch = parse + 5_000
      var stages = [
        FrameStageTime(stage: .read, nanoseconds: read),
        FrameStageTime(stage: .parse, nanoseconds: parse),
        FrameStageTime(stage: .dispatch, nanoseconds: dispatch),
      ]
      if index.isMultiple(of: 2) {
        stages.append(FrameStageTime(stage: .deliveryVirtualDevice, nanoseconds: dispatch + 50_000))
      }
      if index == 100 {
        stages.append(FrameStageTime(stage: .deliveryEndpoint, nanoseconds: dispatch + 700_000))
      }
      return FrameTiming(sequence: UInt64(index), stages: stages)
    }
  }

  private func gap(_ gap: FrameGap, in summary: FrameTimingSummary) -> FrameGapSummary? {
    summary.gaps.first { $0.gap == gap }
  }

  @Test
  func theWindowCountAndSpanAreTheFramesAndTheFirstToLastRead() {
    let summary = FrameTimingSummary(window: Self.window(), lastSeconds: 10)

    #expect(summary.frames == 101)
    #expect(summary.spanNanoseconds == 98 * 1_000_000 + 2_000_000 + 10_000_000)
  }

  @Test
  func theReadIntervalPercentilesAreNearestRank() throws {
    let summary = FrameTimingSummary(window: Self.window(), lastSeconds: 10)

    let interval = try #require(gap(.readToRead, in: summary))
    #expect(interval.samples == 100)
    #expect(interval.p50Nanoseconds == 1_000_000)
    #expect(interval.p99Nanoseconds == 2_000_000)
    #expect(interval.maxNanoseconds == 10_000_000)
  }

  @Test
  func theStallThresholdIsThreeMedianReadIntervalsAndCountsOnlyLongerIntervals() throws {
    let summary = FrameTimingSummary(window: Self.window(), lastSeconds: 10)

    #expect(FrameTimingSummary.stallIntervalMultiplier == 3)
    let stalls = try #require(summary.stalls)
    #expect(stalls.thresholdNanoseconds == 3_000_000)
    #expect(stalls.count == 1)
  }

  @Test
  func anIntervalEqualToTheThresholdIsNotAStall() throws {
    var read: UInt64 = 0
    let window = (0..<5).map { index in
      read += index == 3 ? 3_000_000 : 1_000_000
      return FrameTiming(
        sequence: UInt64(index),
        stages: [FrameStageTime(stage: .read, nanoseconds: read)]
      )
    }

    let stalls = try #require(FrameTimingSummary(window: window, lastSeconds: 10).stalls)

    #expect(stalls == FrameStalls(thresholdNanoseconds: 3_000_000, count: 0))
  }

  @Test
  func theStageGapsAreMeasuredOnTheFramesThatReachedBothStages() throws {
    let summary = FrameTimingSummary(window: Self.window(), lastSeconds: 10)

    let parse = try #require(gap(.readToParse, in: summary))
    #expect(parse.samples == 101)
    #expect(parse.p50Nanoseconds == 20_000)
    #expect(parse.p99Nanoseconds == 40_000)
    #expect(parse.maxNanoseconds == 40_000)

    let dispatch = try #require(gap(.parseToDispatch, in: summary))
    #expect(dispatch.samples == 101)
    #expect(
      [dispatch.p50Nanoseconds, dispatch.p99Nanoseconds, dispatch.maxNanoseconds]
        == [5_000, 5_000, 5_000]
    )

    let device = try #require(gap(.dispatchToDeliveryVirtualDevice, in: summary))
    #expect(device.samples == 51)
    #expect(
      [device.p50Nanoseconds, device.p99Nanoseconds, device.maxNanoseconds]
        == [50_000, 50_000, 50_000]
    )

    let endpoint = try #require(gap(.dispatchToDeliveryEndpoint, in: summary))
    #expect(endpoint.samples == 1)
    #expect(endpoint.maxNanoseconds == 700_000)
  }

  @Test
  func aGapNoFrameMeasuredIsAbsentAndTheGapsKeepPipelineOrder() {
    let window = Self.window().map {
      FrameTiming(
        sequence: $0.sequence,
        stages: $0.stages.filter { $0.stage != .deliveryEndpoint }
      )
    }

    let summary = FrameTimingSummary(window: window, lastSeconds: 10)

    #expect(
      summary.gaps.map(\.gap) == [
        .readToParse, .parseToDispatch, .dispatchToDeliveryVirtualDevice, .readToRead,
      ]
    )
  }

  @Test
  func aStampThatPrecedesTheEarlierStageIsNotASample() throws {
    let window = [
      FrameTiming(
        sequence: 0,
        stages: [
          FrameStageTime(stage: .read, nanoseconds: 500),
          FrameStageTime(stage: .parse, nanoseconds: 400),
        ]
      ),
      FrameTiming(
        sequence: 1,
        stages: [
          FrameStageTime(stage: .read, nanoseconds: 1_000),
          FrameStageTime(stage: .parse, nanoseconds: 1_030),
        ]
      ),
    ]

    let summary = FrameTimingSummary(window: window, lastSeconds: 10)

    let parse = try #require(gap(.readToParse, in: summary))
    #expect(parse.samples == 1)
    #expect(parse.maxNanoseconds == 30)
  }

  @Test
  func oneFrameHasNoReadIntervalAndNoStallRule() {
    let summary = FrameTimingSummary(window: Array(Self.window().prefix(1)), lastSeconds: 10)

    #expect(summary.frames == 1)
    #expect(summary.spanNanoseconds == 0)
    #expect(
      summary.gaps.map(\.gap) == [.readToParse, .parseToDispatch, .dispatchToDeliveryVirtualDevice]
    )
    #expect(summary.stalls == nil)
  }

  @Test
  func anEmptyWindowHasNothingToSummarize() {
    #expect(
      FrameTimingSummary(window: [], lastSeconds: 10)
        == FrameTimingSummary(lastSeconds: 10, frames: 0, spanNanoseconds: 0, gaps: [], stalls: nil)
    )
  }

  @Test
  func theWholeRingKeepsTheStageGapsButMeasuresNoReadIntervalAndNoStall() {
    let summary = FrameTimingSummary(window: Self.window(), lastSeconds: nil)

    #expect(summary.lastSeconds == nil)
    #expect(summary.frames == 101)
    #expect(
      summary.gaps.map(\.gap) == [
        .readToParse, .parseToDispatch, .dispatchToDeliveryVirtualDevice,
        .dispatchToDeliveryEndpoint,
      ]
    )
    #expect(summary.stalls == nil)
  }

  @Test
  func theSnapshotOfARecorderCarriesTheSummaryOfItsWindow() {
    let identifier = LogicalControllerID(vendorID: 1, productID: 2)
    let recorder = FrameTimingRecorder()
    for index in 0..<30 {
      let read = UInt64(index) * 1_000_000
      recorder.parsed(for: identifier, read: read, parse: read + 10_000)
      _ = recorder.dispatched(for: identifier, at: read + 15_000)
    }

    let timings = ControllerFrameTimings(
      controller: "c",
      name: "n",
      window: recorder.window(for: identifier),
      lastSeconds: nil
    )

    #expect(timings.frames.count == FrameTimingRecorder.listedFrames)
    #expect(timings.summary.frames == 30)
    #expect(timings.summary.spanNanoseconds == 29_000_000)
    #expect(timings.summary.lastSeconds == nil)
    #expect(timings.summary.stalls == nil)
  }
}
