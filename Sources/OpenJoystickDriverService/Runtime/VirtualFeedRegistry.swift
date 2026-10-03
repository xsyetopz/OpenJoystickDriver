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
/// A feed closes when its client closes it, when it gets no exchange for `idleTimeout`, or when
/// the service stops.
/// - Note: `@unchecked Sendable` because `lock` guards `sessions` and `stopped`.
final class VirtualFeedRegistry: @unchecked Sendable {
  static let maximumFeeds = 4
  /// Older commands are dropped first when a client does not collect them.
  static let maximumQueuedFeedback = 256

  private final class Session {
    let device: any VirtualFeedDevice
    let identifier: DeviceIdentifier
    var feedback: [ControllerOutputCommand] = []
    /// `ProcessInfo.systemUptime` of the last exchange.
    var lastExchange: TimeInterval
    var watchdog: Task<Void, Never>?

    init(device: any VirtualFeedDevice, identifier: DeviceIdentifier) {
      self.device = device
      self.identifier = identifier
      lastExchange = ProcessInfo.processInfo.systemUptime
    }
  }

  private let factory: VirtualFeedDeviceFactory
  private let idleTimeout: TimeInterval
  private let lock = NSLock()
  private var sessions: [UUID: Session] = [:]
  private var stopped = false

  init(
    factory: @escaping VirtualFeedDeviceFactory,
    idleTimeout: TimeInterval = VirtualFeedExchangeResult.idleTimeoutSeconds
  ) {
    self.factory = factory
    self.idleTimeout = idleTimeout
  }

  func open(profile name: String) async throws -> VirtualFeedSession {
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
      )
    )
    let failure = lock.withLock { () -> VirtualFeedError? in
      if stopped { return .serviceStopped }
      guard sessions.count < Self.maximumFeeds else { return .tooManyFeeds(Self.maximumFeeds) }
      sessions[token] = session
      return nil
    }
    if let failure {
      await device.close()
      throw failure
    }
    do {
      try await device.activate(controller: session.identifier)
    } catch {
      await close(token: token)
      throw VirtualFeedError.activationFailed(String(describing: error))
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

  /// Sends `frame`, when given, and returns the queued output commands; a token with no open
  /// feed returns `closed`.
  func exchange(token: UUID, frame: VirtualFeedFrame?) async throws -> VirtualFeedExchangeResult {
    let taken = lock.withLock { () -> (Session, [ControllerOutputCommand])? in
      guard let session = sessions[token] else { return nil }
      session.lastExchange = ProcessInfo.processInfo.systemUptime
      defer { session.feedback.removeAll() }
      return (session, session.feedback)
    }
    guard let (session, feedback) = taken else {
      return VirtualFeedExchangeResult(feedback: [], closed: true)
    }
    if let frame {
      do {
        try await session.device.send(frame.gamepadState, for: session.identifier)
      } catch {
        guard await close(token: token) else {
          return VirtualFeedExchangeResult(feedback: feedback, closed: true)
        }
        throw error
      }
    }
    return VirtualFeedExchangeResult(feedback: feedback, closed: false)
  }

  /// Removes the feed's virtual controller; false when no open feed has the token.
  @discardableResult
  func close(token: UUID) async -> Bool {
    guard let session = lock.withLock({ sessions.removeValue(forKey: token) }) else {
      return false
    }
    session.watchdog?.cancel()
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
