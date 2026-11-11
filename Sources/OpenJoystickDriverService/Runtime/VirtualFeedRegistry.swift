import Foundation
import OpenJoystickDriverKit

/// The virtual controller one feed publishes.
protocol VirtualFeedDevice: AnyObject, Sendable {
  /// Publishes the virtual controller of `identifier`.
  ///
  /// - Throws: The failure to create the virtual device.
  func activate(controller identifier: LogicalControllerID) async throws
  /// Updates the virtual controller of `identifier` to `state`.
  func send(_ state: RemappingGamepadState, for identifier: LogicalControllerID) async throws
  /// Removes the virtual controller.
  func close() async
}

extension UserSpaceOutputDispatcher: VirtualFeedDevice {}

/// Builds the device for a feed; the handler receives the host's output commands.
typealias VirtualFeedDeviceFactory =
  @Sendable (VirtualHIDProfileID, @escaping UserSpaceOutputDispatcher.OutputCommandHandler)
  throws -> any VirtualFeedDevice

/// Who opened a feed; each pool has its own `VirtualFeedRegistry.maximumFeeds`, so endpoint
/// clients cannot take the feeds of `ojd virtual feed`.
enum VirtualFeedPool: Hashable {
  /// A feed that an endpoint client opened.
  case endpoint
  /// The local service RPC, which `ojd virtual feed` uses.
  case rpc
}

/// Why a feed cannot be opened.
enum VirtualFeedError: LocalizedError, Equatable {
  /// The profile name is not a virtual HID profile.
  case unknownProfile(String)
  /// The pool already holds the most feeds, with that limit.
  case tooManyFeeds(Int)
  /// The service is stopping.
  case serviceStopped
  /// The virtual controller did not start, with the reason.
  case activationFailed(String)

  /// The message that the client sees.
  var errorDescription: String? {
    switch self {
    case .unknownProfile(let profile): "Unknown virtual HID profile: \(profile)."
    case .tooManyFeeds(let limit): "The service already runs \(limit) virtual feeds."
    case .serviceStopped: "The service is stopping."
    case .activationFailed(let detail): "The virtual controller did not start: \(detail)."
    }
  }
}

/// The open virtual feeds: each one publishes a virtual controller that a client drives with
/// frames and that queues the host's output commands for the client.
///
/// Each feed shows its frames in order, each for at least its hold and at least
/// `VirtualFeedExchangeResult.minimumFrameMilliseconds`, counted from when its send returns, so a
/// slow send does not shorten the frame's time or the next one's. A queued frame without a hold
/// gives way to a newer one with the same buttons and d-pad, so that only axis changes coalesce.
///
/// A feed closes when its client closes it, when it gets no exchange for `idleTimeout`, or when
/// the service stops. The idle time counts from the end of the last queued frame's time, so a
/// client that stalls keeps its feed until its queue has played, at most
/// `VirtualFeedExchangeResult.maximumQueuedFrames` frames of up to their hold each. A frame whose
/// send takes longer than its time plus `idleTimeout` closes the feed, so a hung device does not
/// keep its slot.
/// - Note: `@unchecked Sendable` because `lock` guards `sessions`, `reserved`, and `stopped`.
final class VirtualFeedRegistry: @unchecked Sendable {
  /// The most open feeds per `VirtualFeedPool`.
  static let maximumFeeds = 4
  /// How long a virtual controller may take to start before the open fails.
  static let activationTimeoutSeconds: TimeInterval = 2
  /// Older commands are dropped first when a client does not collect them.
  static let maximumQueuedFeedback = 256

  /// One open feed: the source of the frames its client queued, and the virtual device that is
  /// their sink.
  /// - Note: `@unchecked Sendable` because the registry's `lock` guards every mutable member.
  private final class Session: InputSource, @unchecked Sendable {
    /// The virtual controller that the feed publishes.
    let device: any VirtualFeedDevice
    /// Which kind of client feeds the session.
    let origin: InputOrigin
    /// The sink that carries the frames to the device.
    let sink: any OutputSink
    /// The identity of the virtual controller.
    let identifier: LogicalControllerID
    /// The pool that the feed counts against.
    let pool: VirtualFeedPool
    /// The host's output commands that the client has not collected.
    var feedback: [ControllerOutputCommand] = []
    /// Where the host's output commands go as they arrive, in order; nil when the client polls
    /// `exchange` for them.
    let returnSink: (any OutputSink)?
    /// Whether the client is ready for returned commands.
    var returnsFeedback = false
    /// Delivers `feedback` to `returnSink`; nil when it has none to deliver.
    var returner: Task<Void, Never>?
    /// Frames that wait for `player`, oldest first.
    var pending: [VirtualFeedFrame] = []
    /// Shows `pending`; nil when the feed shows its last frame and waits for more.
    var player: Task<Void, Never>?
    /// While `player` shows a frame, the uptime after which its send counts as hung.
    var frameDeadline: TimeInterval?
    /// `clock` time of the last exchange.
    var lastExchange: TimeInterval
    /// The task that closes an idle feed.
    var watchdog: Task<Void, Never>?
    /// Callers of ``VirtualFeedRegistry/waitUntilPlayed(token:)``; each resumes with whether the
    /// queued frames played.
    var playWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    /// Creates the session of a feed that was just built.
    init(
      device: any VirtualFeedDevice,
      identifier: LogicalControllerID,
      pool: VirtualFeedPool,
      returnSink: (any OutputSink)?,
      now: TimeInterval
    ) {
      self.device = device
      self.returnSink = returnSink
      self.origin = pool == .endpoint ? .endpointFeed : .virtualFeed
      self.sink = VirtualFeedDeviceSink(device)
      self.identifier = identifier
      self.pool = pool
      lastExchange = now
    }
  }

  /// Builds the device of a feed.
  private let factory: VirtualFeedDeviceFactory
  /// How long a feed may go without an exchange before it closes, in seconds.
  let idleTimeout: TimeInterval
  /// How long a virtual controller may take to start, in seconds.
  private let activationTimeout: TimeInterval
  /// The time source and sleep of the feeds.
  private let clock: VirtualFeedClock
  /// Guards `sessions`, `reserved` and `stopped`.
  private let lock = NSLock()
  /// The open feeds by token.
  private var sessions: [UUID: Session] = [:]
  /// Whether the registry stopped.
  private var stopped = false
  /// Feeds whose device is being built, so concurrent opens count against the limit.
  private var reserved: [VirtualFeedPool: Int] = [:]

  /// Creates a registry that builds feed devices with `factory`.
  init(
    factory: @escaping VirtualFeedDeviceFactory,
    idleTimeout: TimeInterval = VirtualFeedExchangeResult.idleTimeoutSeconds,
    activationTimeout: TimeInterval = VirtualFeedRegistry.activationTimeoutSeconds,
    clock: VirtualFeedClock = .system
  ) {
    self.factory = factory
    self.idleTimeout = idleTimeout
    self.activationTimeout = activationTimeout
    self.clock = clock
  }

  /// Opens a feed.
  ///
  /// With a `returnSink`, the host's output commands go to it in order through
  /// `OutputSink.consume(_:for:)` once ``startReturningFeedback(token:)`` runs, and
  /// ``exchange(token:frames:countsAsActivity:)`` returns no feedback.
  func open(
    profile name: String,
    pool: VirtualFeedPool = .rpc,
    returnSink: (any OutputSink)? = nil
  ) async throws -> VirtualFeedSession {
    guard let profile = VirtualHIDProfileID(rawValue: name) else {
      throw VirtualFeedError.unknownProfile(name)
    }
    let token = UUID()
    // The slot is taken before the factory runs, so a refused open builds no device.
    try reserveSlot(in: pool)
    let device: any VirtualFeedDevice
    do {
      device = try factory(profile) { [weak self] _, command in
        self?.enqueue(command, for: token)
      }
    } catch {
      lock.withLock { reserved[pool, default: 1] -= 1 }
      throw error
    }
    let identity = profile.identity
    let session = Session(
      device: device,
      identifier: LogicalControllerID(
        vendorID: identity.vendorID,
        productID: identity.productID,
        serialNumber: "feed-\(token.uuidString)"
      ),
      pool: pool,
      returnSink: returnSink,
      now: clock.now()
    )
    let stoppedMeanwhile = lock.withLock { () -> Bool in
      reserved[pool, default: 1] -= 1
      if stopped { return true }
      sessions[token] = session
      return false
    }
    if stoppedMeanwhile {
      await device.close()
      throw VirtualFeedError.serviceStopped
    }
    // A hung activation must not hold the caller, which may block a connection thread.
    let identifier = session.identifier
    let activationFailure: VirtualFeedError?
    do {
      try await withTimeout(seconds: activationTimeout) {
        try await device.activate(controller: identifier)
      }
      activationFailure = nil
    } catch is TimeoutError {
      activationFailure = .activationFailed(
        "it took longer than \(activationTimeout.formatted()) seconds"
      )
    } catch is CancellationError where Task.isCancelled {
      if lock.withLock({ sessions.removeValue(forKey: token) }) != nil {
        Task { await device.close() }
      }
      throw CancellationError()
    } catch {
      activationFailure = .activationFailed(String(describing: error))
    }
    if let activationFailure {
      // The slot frees at once; closing waits for the activation, which may still hang, so the
      // caller does not wait for it.
      if lock.withLock({ sessions.removeValue(forKey: token) }) != nil {
        Task { await device.close() }
      }
      throw activationFailure
    }
    let watching = lock.withLock { () -> Bool in
      guard sessions[token] === session else { return false }
      session.lastExchange = clock.now()
      session.watchdog = Task { [weak self] in await self?.watch(token) }
      return true
    }
    guard watching else { throw VirtualFeedError.serviceStopped }
    return VirtualFeedSession(token: token)
  }

  /// Counts a feed that is about to be built against the limit of `pool`.
  private func reserveSlot(in pool: VirtualFeedPool) throws {
    try lock.withLock {
      if stopped { throw VirtualFeedError.serviceStopped }
      let taken = sessions.values.filter { $0.pool == pool }.count + reserved[pool, default: 0]
      guard taken < Self.maximumFeeds else {
        throw VirtualFeedError.tooManyFeeds(Self.maximumFeeds)
      }
      reserved[pool, default: 0] += 1
    }
  }

  /// Queues as many of `frames` as fit and returns the queued output commands; a token with no open
  /// feed returns `closed`.
  ///
  /// An exchange counts as activity for the idle timeout unless `countsAsActivity` is false, which
  /// a caller that polls for feedback on its own passes.
  func exchange(
    token: UUID,
    frames: [VirtualFeedFrame],
    countsAsActivity: Bool = true
  ) -> VirtualFeedExchangeResult {
    lock.withLock {
      guard let session = sessions[token] else {
        return VirtualFeedExchangeResult(feedback: [], closed: true)
      }
      if countsAsActivity { session.lastExchange = clock.now() }
      let accepted = Self.enqueue(frames, in: session)
      if session.player == nil, !session.pending.isEmpty {
        session.player = Task { [weak self] in await self?.play(token) }
      }
      let feedback = session.returnSink == nil ? session.feedback : []
      defer { if session.returnSink == nil { session.feedback.removeAll() } }
      return VirtualFeedExchangeResult(
        feedback: feedback,
        closed: false,
        accepted: accepted,
        queued: session.pending.count + (session.frameDeadline == nil ? 0 : 1)
      )
    }
  }

  /// Whether a feed with the token is open.
  func isOpen(token: UUID) -> Bool { lock.withLock { sessions[token] != nil } }

  /// Which kind of source the feed with the token is, or nil when none is open.
  func origin(of token: UUID) -> InputOrigin? { lock.withLock { sessions[token]?.origin } }

  /// Starts delivering the host's output commands to the feed's `returnSink`, those queued so far
  /// first.
  ///
  /// The client calls it once it can take them.
  func startReturningFeedback(token: UUID) {
    lock.withLock {
      guard let session = sessions[token] else { return }
      session.returnsFeedback = true
      scheduleReturn(of: session, token: token)
    }
  }

  /// Suspends until every frame queued so far has played, the last one for its full time, and
  /// returns true.
  ///
  /// Returns false when the feed closes first, when no open feed has the token, or when the calling
  /// task is cancelled.
  func waitUntilPlayed(token: UUID) async -> Bool {
    let waiter = UUID()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
        let answer = lock.withLock { () -> Bool? in
          guard let session = sessions[token], !Task.isCancelled else { return false }
          if session.pending.isEmpty, session.player == nil { return true }
          session.playWaiters[waiter] = continuation
          return nil
        }
        if let answer { continuation.resume(returning: answer) }
      }
    } onCancel: {
      let continuation = lock.withLock {
        sessions[token]?.playWaiters.removeValue(forKey: waiter)
      }
      continuation?.resume(returning: false)
    }
  }

  /// Resumes and forgets the waiters of `session`.
  ///
  /// The caller does not hold `lock`.
  private func resumePlayWaiters(of session: Session, played: Bool) {
    let waiters = lock.withLock { () -> [CheckedContinuation<Bool, Never>] in
      defer { session.playWaiters.removeAll() }
      return Array(session.playWaiters.values)
    }
    for waiter in waiters { waiter.resume(returning: played) }
  }

  /// Removes the feed's virtual controller; false when no open feed has the token.
  @discardableResult
  func close(token: UUID) async -> Bool {
    guard let session = lock.withLock({ sessions.removeValue(forKey: token) }) else {
      return false
    }
    resumePlayWaiters(of: session, played: false)
    session.watchdog?.cancel()
    session.player?.cancel()
    session.returner?.cancel()
    await session.device.close()
    return true
  }

  /// Closes every feed and refuses further ones.
  func stop() async {
    let closing = lock.withLock { () -> [Session] in
      stopped = true
      defer { sessions.removeAll() }
      return Array(sessions.values)
    }
    for session in closing {
      resumePlayWaiters(of: session, played: false)
      session.watchdog?.cancel()
      session.player?.cancel()
      session.returner?.cancel()
      await session.device.close()
    }
  }

  /// The number of open feeds.
  var openFeedCount: Int { lock.withLock { sessions.count } }

  /// Queues the host's output command for the client of the feed `token`, dropping the oldest ones
  /// past the limit.
  private func enqueue(_ command: ControllerOutputCommand, for token: UUID) {
    lock.withLock {
      guard let session = sessions[token] else { return }
      session.feedback.append(command)
      let excess = session.feedback.count - Self.maximumQueuedFeedback
      if excess > 0 { session.feedback.removeFirst(excess) }
      scheduleReturn(of: session, token: token)
    }
  }

  /// Starts the session's `returner` when it has a sink that is ready and one is not running.
  ///
  /// The caller holds `lock`.
  private func scheduleReturn(of session: Session, token: UUID) {
    guard session.returnSink != nil, session.returnsFeedback, session.returner == nil,
      !session.feedback.isEmpty
    else { return }
    session.returner = Task { [weak self] in await self?.returnFeedback(token) }
  }

  /// Hands the feed's queued output commands to its `returnSink` one at a time, so the client
  /// sees them in the order the host sent them; stops when none are left.
  private func returnFeedback(_ token: UUID) async {
    while !Task.isCancelled {
      let next = lock.withLock { () -> (Session, [ControllerOutputCommand])? in
        guard let session = sessions[token] else { return nil }
        guard !session.feedback.isEmpty else {
          session.returner = nil
          return nil
        }
        defer { session.feedback.removeAll() }
        return (session, session.feedback)
      }
      guard let (session, commands) = next, let sink = session.returnSink else { return }
      for command in commands {
        // A refused command is gone, as a rumble line the connection dropped always was.
        try? await sink.consume(command, for: session.identifier)
      }
    }
  }

  /// Adds `frames` to the session's queue, oldest first, until it is full; returns how many it
  /// took.
  ///
  /// The caller holds `lock`.
  private static func enqueue(_ frames: [VirtualFeedFrame], in session: Session) -> Int {
    var accepted = 0
    for frame in frames {
      if let last = session.pending.last, replaces(last, with: frame) {
        session.pending[session.pending.count - 1] = frame
      } else if session.pending.count < VirtualFeedExchangeResult.maximumQueuedFrames {
        session.pending.append(frame)
      } else {
        break
      }
      accepted += 1
    }
    return accepted
  }

  /// Whether `frame` can take the place of the queued `last` without losing a press, a release,
  /// or a hold.
  private static func replaces(_ last: VirtualFeedFrame, with frame: VirtualFeedFrame) -> Bool {
    (last.holdMilliseconds ?? 0) == 0 && (frame.holdMilliseconds ?? 0) == 0
      && last.buttons == frame.buttons && last.dpad == frame.dpad
  }

  /// Sends the feed's queued frames in order and waits out each one's time from the moment its send
  /// returns; stops when the queue is empty.
  ///
  /// A failed send closes the feed.
  private func play(_ token: UUID) async {
    var playedUntil: TimeInterval?
    var finished: Session?
    while !Task.isCancelled {
      let next = lock.withLock { () -> (Session, VirtualFeedFrame, Int)? in
        guard let session = sessions[token] else { return nil }
        let now = clock.now()
        guard !session.pending.isEmpty else {
          session.player = nil
          session.frameDeadline = nil
          // The idle time starts at the end of the last frame's time, not at the later moment
          // this task runs.
          session.lastExchange = max(session.lastExchange, playedUntil ?? now)
          finished = session
          return nil
        }
        let frame = session.pending.removeFirst()
        let milliseconds = max(
          frame.holdMilliseconds ?? 0,
          VirtualFeedExchangeResult.minimumFrameMilliseconds
        )
        session.frameDeadline = now + TimeInterval(milliseconds) / 1000 + idleTimeout
        return (session, frame, milliseconds)
      }
      guard let (session, frame, milliseconds) = next else {
        if let finished { resumePlayWaiters(of: finished, played: true) }
        return
      }
      do {
        try await session.produce(.gamepad(frame.gamepadState, for: session.identifier))
        let end = clock.now() + TimeInterval(milliseconds) / 1000
        try await clock.sleep(end)
        playedUntil = end
      } catch is CancellationError {
        return
      } catch {
        await close(token: token)
        return
      }
    }
  }

  /// The `clock` time of each open feed's last exchange; lets a test see that an exchange landed.
  var lastExchangeTimes: [TimeInterval] { lock.withLock { sessions.values.map(\.lastExchange) } }

  /// Closes the feed once it goes `idleTimeout` without an exchange, counted from the end of the
  /// last frame's time, or once a frame's send hangs past its `frameDeadline`.
  private func watch(_ token: UUID) async {
    while !Task.isCancelled {
      // The deadline and the time it is compared with are read under one lock, so an exchange
      // that lands between them cannot make a feed look idle.
      let snapshot = lock.withLock { () -> (deadline: TimeInterval, now: TimeInterval)? in
        guard let session = sessions[token] else { return nil }
        let now = clock.now()
        if let frameDeadline = session.frameDeadline { return (frameDeadline, now) }
        // `player` is about to show the waiting frames.
        if !session.pending.isEmpty { return (.infinity, now) }
        return (session.lastExchange + idleTimeout, now)
      }
      guard let (deadline, now) = snapshot else { return }
      guard deadline > now else {
        await close(token: token)
        return
      }
      try? await clock.sleep(min(deadline, now + idleTimeout))
    }
  }
}

/// The virtual device of one feed as the sink of the feed's frames.
final class VirtualFeedDeviceSink: OutputSink {
  /// Marks the frames as delivered to a virtual device.
  let destination = OutputDestination.virtualDevice
  /// The device that takes the frames.
  private let device: any VirtualFeedDevice

  /// Creates a sink for `device`.
  init(_ device: any VirtualFeedDevice) { self.device = device }

  /// Sends the gamepad state of `frame` to the device.
  ///
  /// - Throws: ``StreamBoundaryError/unsupported(_:)`` for a frame that is not a gamepad state, or
  ///   the failure of the device.
  func consume(
    _ frame: StreamFrame,
    onDelivered: @escaping @Sendable () -> Void
  ) async throws {
    guard case .gamepad(let state, let identifier) = frame else {
      throw StreamBoundaryError.unsupported(destination)
    }
    try await device.send(state, for: identifier)
    onDelivered()
  }
}
