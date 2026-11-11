import Foundation

/// A span between two points of a controller's frames.
///
/// The raw values are the stable identifiers that `ojd diagnose` prints and
/// `cli-output.schema.json` lists.
public enum FrameGap: String, Codable, CaseIterable, Sendable {
  /// From a frame's `Read` stage to its `Parse` stage.
  case readToParse = "ReadToParse"
  /// From a frame's `Parse` stage to its `Dispatch` stage.
  case parseToDispatch = "ParseToDispatch"
  /// From a frame's `Dispatch` stage to its `DeliveryVirtualDevice` stage.
  case dispatchToDeliveryVirtualDevice = "DispatchToDeliveryVirtualDevice"
  /// From a frame's `Dispatch` stage to its `DeliveryEndpoint` stage.
  case dispatchToDeliveryEndpoint = "DispatchToDeliveryEndpoint"
  /// From the `Read` stage of the frame before a frame to its own `Read` stage.
  case readToRead = "ReadToRead"
}

/// The median, the 99th percentile and the maximum of one ``FrameGap`` over a window.
public struct FrameGapSummary: Codable, Equatable, Sendable {
  /// The gap that the figures describe.
  public let gap: FrameGap
  /// The spans the gap was measured on; a frame that did not reach both stages adds none.
  public let samples: Int
  /// The median span in nanoseconds.
  public let p50Nanoseconds: UInt64
  /// The 99th percentile span in nanoseconds.
  public let p99Nanoseconds: UInt64
  /// The longest span in nanoseconds.
  public let maxNanoseconds: UInt64

  /// Creates a summary from its values.
  public init(
    gap: FrameGap,
    samples: Int,
    p50Nanoseconds: UInt64,
    p99Nanoseconds: UInt64,
    maxNanoseconds: UInt64
  ) {
    self.gap = gap
    self.samples = samples
    self.p50Nanoseconds = p50Nanoseconds
    self.p99Nanoseconds = p99Nanoseconds
    self.maxNanoseconds = maxNanoseconds
  }
}

/// The read intervals of a window that are longer than the stall threshold.
public struct FrameStalls: Codable, Equatable, Sendable {
  /// ``FrameTimingSummary/stallIntervalMultiplier`` times the median read interval.
  public let thresholdNanoseconds: UInt64
  /// The read intervals longer than ``thresholdNanoseconds``.
  public let count: Int

  /// Creates stalls from their threshold and count.
  public init(thresholdNanoseconds: UInt64, count: Int) {
    self.thresholdNanoseconds = thresholdNanoseconds
    self.count = count
  }
}

/// What the frame window of one controller says about stutter.
///
/// A gap is measured on the frames that reached both of its stages, so a frame without a delivery
/// stage adds no sample to that delivery gap. A pair of stamps whose later one is earlier than the
/// first is not a sample. A percentile is the nearest-rank value: the sample at 1-based rank
/// `ceil(percent * count / 100)` of the sorted samples.
///
/// A read interval is the time between the `Read` stamps of two consecutive frames. A report that
/// a newer one replaced before dispatch is no frame, so the interval spans it.
///
/// A stall is a read interval longer than ``stallIntervalMultiplier`` times the median read
/// interval of the window. Read intervals and stalls are measured only on a window of the last
/// ``lastSeconds`` seconds, which the user fills with constant input: a controller that sends a
/// report only when an input changes leaves a gap for each pause, and the whole ring holds the
/// pauses before and after the input. The threshold follows the report rate of the controller,
/// so the same rule fits a 125 Hz controller (8 ms) and a 1000 Hz one (1 ms), where one fixed
/// limit would miss the first or flag the second. An interval equal to the threshold is not a
/// stall.
public struct FrameTimingSummary: Codable, Equatable, Sendable {
  /// The multiple of the median read interval above which a read interval is a stall.
  public static let stallIntervalMultiplier: UInt64 = 3

  /// The seconds before the service answered that the window covers; absent for the whole ring.
  public let lastSeconds: Int?
  /// The frames in the window.
  public let frames: Int
  /// The time from the first to the last `Read` stamp of the window; 0 for fewer than two frames.
  public let spanNanoseconds: UInt64
  /// One summary per ``FrameGap`` that has a sample, in the order of `FrameGap.allCases`.
  public let gaps: [FrameGapSummary]
  /// Absent for the whole ring and when the window holds fewer than two frames.
  public let stalls: FrameStalls?

  /// Creates a summary from its values.
  public init(
    lastSeconds: Int?,
    frames: Int,
    spanNanoseconds: UInt64,
    gaps: [FrameGapSummary],
    stalls: FrameStalls?
  ) {
    self.lastSeconds = lastSeconds
    self.frames = frames
    self.spanNanoseconds = spanNanoseconds
    self.gaps = gaps
    self.stalls = stalls
  }

  /// The summary of `window`, oldest frame first, which holds the frames of the last
  /// `lastSeconds` seconds or, for nil, the whole ring.
  public init(window: [FrameTiming], lastSeconds: Int?) {
    let reads = window.compactMap { Self.time(of: .read, in: $0) }
    let intervals =
      lastSeconds == nil
      ? [] : zip(reads, reads.dropFirst()).compactMap { Self.elapsed(from: $0, to: $1) }
    let samples: [FrameGap: [UInt64]] = [
      .readToParse: Self.elapsed(in: window, from: .read, to: .parse),
      .parseToDispatch: Self.elapsed(in: window, from: .parse, to: .dispatch),
      .dispatchToDeliveryVirtualDevice: Self.elapsed(
        in: window,
        from: .dispatch,
        to: .deliveryVirtualDevice
      ),
      .dispatchToDeliveryEndpoint: Self.elapsed(in: window, from: .dispatch, to: .deliveryEndpoint),
      .readToRead: intervals,
    ]
    let stalls = Self.percentile(50, of: intervals.sorted()).map { median in
      let threshold = median * Self.stallIntervalMultiplier
      return FrameStalls(
        thresholdNanoseconds: threshold,
        count: intervals.filter { $0 > threshold }.count
      )
    }
    let span = reads.first.flatMap { first in
      reads.last.flatMap { Self.elapsed(from: first, to: $0) }
    }
    self.init(
      lastSeconds: lastSeconds,
      frames: window.count,
      spanNanoseconds: span ?? 0,
      gaps: FrameGap.allCases.compactMap { gap in
        let sorted = (samples[gap] ?? []).sorted()
        guard let median = Self.percentile(50, of: sorted),
          let high = Self.percentile(99, of: sorted),
          let maximum = sorted.last
        else { return nil }
        return FrameGapSummary(
          gap: gap,
          samples: sorted.count,
          p50Nanoseconds: median,
          p99Nanoseconds: high,
          maxNanoseconds: maximum
        )
      },
      stalls: stalls
    )
  }

  /// The time from `start` to `end`; nil when `end` is earlier.
  private static func elapsed(from start: UInt64, to end: UInt64) -> UInt64? {
    end >= start ? end - start : nil
  }

  /// The spans from stage `first` to stage `second` of each frame of `window` that has both stamps
  /// in order.
  private static func elapsed(
    in window: [FrameTiming],
    from first: FrameStage,
    to second: FrameStage
  ) -> [UInt64] {
    window.compactMap { frame in
      guard let start = time(of: first, in: frame), let end = time(of: second, in: frame)
      else { return nil }
      return elapsed(from: start, to: end)
    }
  }

  /// The stamp of `stage` on `frame`, in nanoseconds of the uptime clock; nil when the frame did
  /// not reach it.
  static func time(of stage: FrameStage, in frame: FrameTiming) -> UInt64? {
    frame.stages.first { $0.stage == stage }?.nanoseconds
  }

  /// The nearest-rank `percent` percentile of `sorted`; nil when `sorted` is empty.
  private static func percentile(_ percent: Int, of sorted: [UInt64]) -> UInt64? {
    guard !sorted.isEmpty else { return nil }
    return sorted[(percent * sorted.count + 99) / 100 - 1]
  }
}
