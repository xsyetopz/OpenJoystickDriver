import Foundation

/// One stage a controller frame passes through, in pipeline order.
///
/// The raw values are the stable identifiers that `ojd diagnose` prints and
/// `cli-output.schema.json` lists.
public enum FrameStage: String, Codable, CaseIterable, Sendable {
  /// The report arrived from the controller.
  case read = "Read"
  /// The protocol driver finished parsing the report into a controller event.
  case parse = "Parse"
  /// The pipeline handed the event to the output dispatcher.
  case dispatch = "Dispatch"
  /// The output dispatcher finished with the event, so the virtual device has the report.
  case deliveryVirtualDevice = "DeliveryVirtualDevice"
  /// The endpoint sent a stream line carrying the controller's state, which may be newer than the
  /// frame it is recorded on: the endpoint reads the latest state on its own poll.
  case deliveryEndpoint = "DeliveryEndpoint"
}

/// The time a frame reached `stage`, in nanoseconds of the monotonic uptime clock.
public struct FrameStageTime: Codable, Equatable, Sendable {
  /// The stage the frame reached.
  public let stage: FrameStage
  /// The uptime when it reached the stage.
  public let nanoseconds: UInt64

  /// Creates a stage time from its values.
  public init(stage: FrameStage, nanoseconds: UInt64) {
    self.stage = stage
    self.nanoseconds = nanoseconds
  }
}

/// The stages one frame reached, in the order it reached them.
public struct FrameTiming: Codable, Equatable, Sendable {
  /// Counts the frames that reached dispatch for this controller since its pipeline started.
  public let sequence: UInt64
  /// The stamps of the stages the frame reached.
  public let stages: [FrameStageTime]

  /// Creates a frame timing from its values.
  public init(sequence: UInt64, stages: [FrameStageTime]) {
    self.sequence = sequence
    self.stages = stages
  }
}

/// The newest frames of one connected controller, oldest first, and the summary of its window.
public struct ControllerFrameTimings: Codable, Equatable, Sendable {
  /// The ID from `ojd controller list`.
  public let controller: String
  /// The controller's name.
  public let name: String
  /// The newest ``FrameTimingRecorder/listedFrames`` frames of the window.
  public let frames: [FrameTiming]
  /// The summary of the whole window, not only of ``frames``.
  public let summary: FrameTimingSummary

  /// Creates the timings of a controller from their values.
  public init(
    controller: String,
    name: String,
    frames: [FrameTiming],
    summary: FrameTimingSummary
  ) {
    self.controller = controller
    self.name = name
    self.frames = frames
    self.summary = summary
  }

  /// The timings of a controller whose frame window is `window`, oldest frame first: the frames of
  /// the last `lastSeconds` seconds or, for nil, the whole ring.
  init(controller: String, name: String, window: [FrameTiming], lastSeconds: Int?) {
    self.init(
      controller: controller,
      name: name,
      frames: Array(window.suffix(FrameTimingRecorder.listedFrames)),
      summary: FrameTimingSummary(window: window, lastSeconds: lastSeconds)
    )
  }
}

/// Arguments of `getFrameTimings`: the seconds of the uptime clock the payload covers, counted
/// back from the moment the service answers; nil covers the whole ring.
public struct LocalServiceRPCFrameTimingsArguments: Codable, Equatable, Sendable {
  /// The seconds to cover; nil covers the whole ring.
  public let lastSeconds: Int?

  /// Creates arguments for the last `lastSeconds` seconds, or for the whole ring when nil.
  public init(lastSeconds: Int?) { self.lastSeconds = lastSeconds }
}

/// The result of `ApplicationServiceClient.getFrameTimings(lastSeconds:)`.
public struct ApplicationServiceFrameTimingsPayload: Codable, Equatable, Sendable {
  /// The timings of each connected controller.
  public let controllers: [ControllerFrameTimings]

  /// Creates a payload from the timings of the controllers.
  public init(controllers: [ControllerFrameTimings]) { self.controllers = controllers }
}

/// Records when frames reach each pipeline stage, for `ojd diagnose`.
///
/// It keeps the newest ``windowCapacity`` frames per controller in a fixed ring, so memory stays
/// bounded and a new frame replaces the oldest in constant time. A frame enters the ring when it
/// is dispatched; reports that never reach dispatch leave no entry.
public final class FrameTimingRecorder: Sendable {
  /// The newest frames of the window that `ojd diagnose` lists with every stage stamp.
  public static let listedFrames = 8

  /// The seconds of frames the ring holds at the highest report rate of 1000 Hz. A 10-second
  /// stick sweep fits whole, with time left to run `ojd diagnose` after it.
  public static let windowSeconds = 15

  /// The seconds a request for the last frames may ask for.
  public static let windowSecondsRange = 1...windowSeconds

  /// The frames kept per controller: ``windowSeconds`` at 1000 Hz.
  public static let windowCapacity = windowSeconds * 1_000

  /// A report that is parsed and waits for dispatch.
  private struct Pending {
    /// The `Read` stamp.
    let read: UInt64
    /// The `Parse` stamp.
    let parse: UInt64
  }

  /// The frame ring of one controller.
  private struct Track {
    /// The newest parsed report, which the next dispatch turns into a frame; nil when none waits.
    var pending: Pending?
    /// The sequence the next frame takes.
    var nextSequence: UInt64 = 0
    /// The frame of sequence `n` sits in slot `n % windowCapacity` until the frame
    /// `windowCapacity` sequences later takes the slot.
    var slots = [FrameTiming?](repeating: nil, count: FrameTimingRecorder.windowCapacity)

    /// The sequence of the newest frame; nil before the first frame.
    var newestSequence: UInt64? { nextSequence > 0 ? nextSequence - 1 : nil }

    /// The slot that holds the frame of `sequence`.
    private func slot(of sequence: UInt64) -> Int { Int(sequence % UInt64(slots.count)) }

    /// Starts a frame from the pending report at the dispatch stage and returns its sequence, or
    /// nil when no parsed report is pending.
    mutating func dispatch(at nanoseconds: UInt64) -> UInt64? {
      guard let pending else { return nil }
      self.pending = nil
      let sequence = nextSequence
      nextSequence += 1
      slots[slot(of: sequence)] = FrameTiming(
        sequence: sequence,
        stages: [
          FrameStageTime(stage: .read, nanoseconds: pending.read),
          FrameStageTime(stage: .parse, nanoseconds: pending.parse),
          FrameStageTime(stage: .dispatch, nanoseconds: nanoseconds),
        ]
      )
      return sequence
    }

    /// Adds `stage` to the frame `sequence`, unless the ring already replaced it.
    mutating func append(_ stage: FrameStage, at nanoseconds: UInt64, toSequence sequence: UInt64) {
      let index = slot(of: sequence)
      guard let frame = slots[index], frame.sequence == sequence else { return }
      slots[index] = FrameTiming(
        sequence: sequence,
        stages: frame.stages + [FrameStageTime(stage: stage, nanoseconds: nanoseconds)]
      )
    }

    /// The newest `limit` frames, oldest first.
    func newest(_ limit: Int) -> [FrameTiming] {
      let first = nextSequence - min(nextSequence, UInt64(limit))
      return (first..<nextSequence).compactMap { slots[slot(of: $0)] }
    }
  }

  /// The frame ring of each controller.
  private let tracks = Locked<[LogicalControllerID: Track]>([:])

  /// Creates a recorder with no frames.
  public init() {}

  /// Notes the newest parsed report of `identifier`; a later report replaces it.
  func parsed(for identifier: LogicalControllerID, read: UInt64, parse: UInt64) {
    tracks.withLock { $0[identifier, default: Track()].pending = Pending(read: read, parse: parse) }
  }

  /// Starts a frame from the pending report at the dispatch stage and returns its sequence, or nil
  /// when no parsed report is pending.
  func dispatched(for identifier: LogicalControllerID, at nanoseconds: UInt64) -> UInt64? {
    tracks.withLock { $0[identifier]?.dispatch(at: nanoseconds) }
  }

  /// Adds the virtual device delivery to the frame `sequence`, unless the ring already dropped it.
  func virtualDeviceDelivered(
    sequence: UInt64,
    for identifier: LogicalControllerID,
    at nanoseconds: UInt64
  ) {
    tracks.withLock { tracks in
      tracks[identifier]?.append(.deliveryVirtualDevice, at: nanoseconds, toSequence: sequence)
      return
    }
  }

  /// Adds the endpoint delivery to the newest frame of `identifier`.
  public func endpointDelivered(for identifier: LogicalControllerID, at nanoseconds: UInt64) {
    tracks.withLock { tracks in
      guard let sequence = tracks[identifier]?.newestSequence else { return }
      tracks[identifier]?.append(.deliveryEndpoint, at: nanoseconds, toSequence: sequence)
    }
  }

  /// The newest ``listedFrames`` frames of `identifier`, oldest first.
  public func frames(for identifier: LogicalControllerID) -> [FrameTiming] {
    tracks.withLock { $0[identifier]?.newest(Self.listedFrames) ?? [] }
  }

  /// Every frame the ring holds for `identifier`, oldest first.
  public func window(for identifier: LogicalControllerID) -> [FrameTiming] {
    tracks.withLock { $0[identifier]?.newest(Self.windowCapacity) ?? [] }
  }

  /// The frames of ``window(for:)`` whose `Read` stamp lies within `lastSeconds` seconds before
  /// `now`, oldest first. `now` is on the uptime clock the pipeline stamps with.
  func window(
    for identifier: LogicalControllerID,
    lastSeconds: Int,
    now: UInt64
  ) -> [FrameTiming] {
    let span = UInt64(lastSeconds) * 1_000_000_000
    let oldest = now >= span ? now - span : 0
    return window(for: identifier).filter {
      FrameTimingSummary.time(of: .read, in: $0).map { $0 >= oldest } ?? false
    }
  }

  /// Forgets `identifier` once its pipeline stops.
  func forget(_ identifier: LogicalControllerID) {
    tracks.withLock { _ = $0.removeValue(forKey: identifier) }
  }
}
