import Foundation
import OpenJoystickDriverKit

/// The virtual controller one feed publishes.
protocol VirtualFeedDevice: AnyObject, Sendable {
  func activate(controller identifier: DeviceIdentifier) async throws
  func send(_ state: RemappingGamepadState, for identifier: DeviceIdentifier) async throws
  func close() async
}

extension UserSpaceOutputDispatcher: VirtualFeedDevice {}

/// Builds the device for a feed; the handler receives the host's output commands.
typealias VirtualFeedDeviceFactory =
  @Sendable (VirtualHIDProfileID, @escaping UserSpaceOutputDispatcher.OutputCommandHandler)
  throws -> any VirtualFeedDevice

/// Who opened a feed; each pool has its own `VirtualFeedRegistry.maximumFeeds`, so endpoint
/// clients cannot take the feeds of `ojd virtual feed`.
enum VirtualFeedPool {
  case endpoint
  /// The local service RPC, which `ojd virtual feed` uses.
  case rpc
}

enum VirtualFeedError: LocalizedError, Equatable {
  case unknownProfile(String)
  case tooManyFeeds(Int)
  case serviceStopped
  case activationFailed(String)

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
/// `VirtualFeedExchangeResult.minimumFrameMilliseconds`. A queued frame without a hold gives way
/// to a newer one with the same buttons and d-pad, so that only axis changes coalesce.
///
/// A feed closes when its client closes it, when it gets no exchange for `idleTimeout`, or when
/// the service stops.
/// - Note: `@unchecked Sendable` because `lock` guards `sessions` and `stopped`.
final class VirtualFeedRegistry: @unchecked Sendable {
  /// The most open feeds per `VirtualFeedPool`.
  static let maximumFeeds = 4
  /// How long a virtual controller may take to start before the open fails.
  static let activationTimeoutSeconds: TimeInterval = 2
  /// Older commands are dropped first when a client does not collect them.
  static let maximumQueuedFeedback = 256

  private final class Session {
    let device: any VirtualFeedDevice
    let identifier: DeviceIdentifier
    let pool: VirtualFeedPool
    var feedback: [ControllerOutputCommand] = []
    /// Frames that wait for `player`, oldest first.
    var pending: [VirtualFeedFrame] = []
    /// Shows `pending`; nil when the feed shows its last frame and waits for more.
    var player: Task<Void, Never>?
    /// Whether `player` waits out the time of a frame it sent.
    var showing = false
    /// `ProcessInfo.systemUptime` of the last exchange.
    var lastExchange: TimeInterval
    var watchdog: Task<Void, Never>?

    init(device: any VirtualFeedDevice, identifier: DeviceIdentifier, pool: VirtualFeedPool) {
      self.device = device
      self.identifier = identifier
      self.pool = pool
      lastExchange = ProcessInfo.processInfo.systemUptime
    }
  }

  private let factory: VirtualFeedDeviceFactory
  private let idleTimeout: TimeInterval
  private let activationTimeout: TimeInterval
  private let lock = NSLock()
  private var sessions: [UUID: Session] = [:]
  private var stopped = false

  init(
    factory: @escaping VirtualFeedDeviceFactory,
    idleTimeout: TimeInterval = VirtualFeedExchangeResult.idleTimeoutSeconds,
    activationTimeout: TimeInterval = VirtualFeedRegistry.activationTimeoutSeconds
  ) {
    self.factory = factory
    self.idleTimeout = idleTimeout
    self.activationTimeout = activationTimeout
  }

  func open(profile name: String, pool: VirtualFeedPool = .rpc) async throws -> VirtualFeedSession {
    guard let profile = VirtualHIDProfileID(rawValue: name) else {
      throw VirtualFeedError.unknownProfile(name)
    }
    let token = UUID()
    let device = try factory(profile) { [weak self] _, command in
      self?.enqueue(command, for: token)
    }
    let identity = profile.identity
    let session = Session(
      device: device,
      identifier: DeviceIdentifier(
        vendorID: identity.vendorID,
        productID: identity.productID,
        serialNumber: "feed-\(token.uuidString)"
      ),
      pool: pool
    )
    let failure = lock.withLock { () -> VirtualFeedError? in
      if stopped { return .serviceStopped }
      guard sessions.values.filter({ $0.pool == pool }).count < Self.maximumFeeds else {
        return .tooManyFeeds(Self.maximumFeeds)
      }
      sessions[token] = session
      return nil
    }
    if let failure {
      await device.close()
      throw failure
    }
    // A hung activation must not hold the caller, which may block a connection thread.
    let identifier = session.identifier
    let activation = await withTimeout(seconds: activationTimeout) {
      () async -> Result<Void, any Error> in
      do { return .success(try await device.activate(controller: identifier)) } catch {
        return .failure(error)
      }
    }
    guard case .success = activation else {
      // The slot frees at once; closing waits for the activation, which may still hang, so the
      // caller does not wait for it.
      if lock.withLock({ sessions.removeValue(forKey: token) }) != nil {
        Task { await device.close() }
      }
      if Task.isCancelled { throw CancellationError() }
      if case .failure(let error) = activation {
        throw VirtualFeedError.activationFailed(String(describing: error))
      }
      throw VirtualFeedError.activationFailed(
        "it took longer than \(activationTimeout.formatted()) seconds"
      )
    }
    let watching = lock.withLock { () -> Bool in
      guard sessions[token] === session else { return false }
      session.lastExchange = ProcessInfo.processInfo.systemUptime
      session.watchdog = Task { [weak self] in await self?.watch(token) }
      return true
    }
    guard watching else { throw VirtualFeedError.serviceStopped }
    return VirtualFeedSession(token: token)
  }

  /// Queues as many of `frames` as fit and returns the queued output commands; a token with no
  /// open feed returns `closed`.
  func exchange(token: UUID, frames: [VirtualFeedFrame]) -> VirtualFeedExchangeResult {
    lock.withLock {
      guard let session = sessions[token] else {
        return VirtualFeedExchangeResult(feedback: [], closed: true)
      }
      session.lastExchange = ProcessInfo.processInfo.systemUptime
      let accepted = Self.enqueue(frames, in: session)
      if session.player == nil, !session.pending.isEmpty {
        session.player = Task { [weak self] in await self?.play(token) }
      }
      defer { session.feedback.removeAll() }
      return VirtualFeedExchangeResult(
        feedback: session.feedback,
        closed: false,
        accepted: accepted,
        queued: session.pending.count + (session.showing ? 1 : 0)
      )
    }
  }

  /// Removes the feed's virtual controller; false when no open feed has the token.
  @discardableResult
  func close(token: UUID) async -> Bool {
    guard let session = lock.withLock({ sessions.removeValue(forKey: token) }) else {
      return false
    }
    session.watchdog?.cancel()
    session.player?.cancel()
    await session.device.close()
    return true
  }

  /// Closes every feed and refuses new ones.
  func stop() async {
    let closing = lock.withLock { () -> [Session] in
      stopped = true
      defer { sessions.removeAll() }
      return Array(sessions.values)
    }
    for session in closing {
      session.watchdog?.cancel()
      session.player?.cancel()
      await session.device.close()
    }
  }

  var openFeedCount: Int { lock.withLock { sessions.count } }

  private func enqueue(_ command: ControllerOutputCommand, for token: UUID) {
    lock.withLock {
      guard let session = sessions[token] else { return }
      session.feedback.append(command)
      let excess = session.feedback.count - Self.maximumQueuedFeedback
      if excess > 0 { session.feedback.removeFirst(excess) }
    }
  }

  /// Adds `frames` to the session's queue, oldest first, until it is full; returns how many it
  /// took. The caller holds `lock`.
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

  /// Sends the feed's queued frames in order and waits out each one's time; stops when the queue
  /// is empty. A failed send closes the feed.
  private func play(_ token: UUID) async {
    while !Task.isCancelled {
      let next = lock.withLock { () -> (Session, VirtualFeedFrame)? in
        guard let session = sessions[token] else { return nil }
        guard !session.pending.isEmpty else {
          session.player = nil
          session.showing = false
          return nil
        }
        session.showing = true
        return (session, session.pending.removeFirst())
      }
      guard let (session, frame) = next else { return }
      do {
        try await session.device.send(frame.gamepadState, for: session.identifier)
        let milliseconds = max(
          frame.holdMilliseconds ?? 0,
          VirtualFeedExchangeResult.minimumFrameMilliseconds
        )
        try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
      } catch is CancellationError {
        return
      } catch {
        await close(token: token)
        return
      }
    }
  }

  /// Closes the feed once it goes `idleTimeout` without an exchange.
  private func watch(_ token: UUID) async {
    while !Task.isCancelled {
      let deadline = lock.withLock { sessions[token].map { $0.lastExchange + idleTimeout } }
      guard let deadline else { return }
      let remaining = deadline - ProcessInfo.processInfo.systemUptime
      guard remaining > 0 else {
        await close(token: token)
        return
      }
      try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
    }
  }
}
