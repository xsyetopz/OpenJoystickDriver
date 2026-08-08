import Foundation
import OpenJoystickDriverKit

@testable import OpenJoystickDriver

enum RemappingRouterTrace: Equatable {
  case compatibility([ControllerEvent], DeviceIdentifier)
  case compatibilityStop(DeviceIdentifier)
  case system(RemappingSystemInputAction)
}

final class RemappingRouterRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var entries: [RemappingRouterTrace] = []

  func append(_ entry: RemappingRouterTrace) { lock.withLock { entries.append(entry) } }

  func snapshot() -> [RemappingRouterTrace] { lock.withLock { entries } }

  func removeAll() { lock.withLock { entries.removeAll() } }
}

final class RemappingRouterCompatibility: OutputDispatcher, ControllerLifecycleListener,
  @unchecked Sendable
{
  private let lock = NSLock()
  private let recorder: RemappingRouterRecorder
  private let dispatchCheckpoint: @Sendable () async -> Void
  private let checkpointAfterSuppressionCheck: Bool
  private var suppressed = false

  var suppressOutput: Bool {
    get { lock.withLock { suppressed } }
    set { lock.withLock { suppressed = newValue } }
  }

  init(
    recorder: RemappingRouterRecorder,
    dispatchCheckpoint: @escaping @Sendable () async -> Void = {},
    checkpointAfterSuppressionCheck: Bool = false
  ) {
    self.recorder = recorder
    self.dispatchCheckpoint = dispatchCheckpoint
    self.checkpointAfterSuppressionCheck = checkpointAfterSuppressionCheck
  }

  func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {
    if checkpointAfterSuppressionCheck {
      guard !suppressOutput else { return }
      await dispatchCheckpoint()
      recorder.append(.compatibility(events, identifier))
      return
    }
    await dispatchCheckpoint()
    await Task.yield()
    guard !suppressOutput else { return }
    recorder.append(.compatibility(events, identifier))
  }

  func controllerDidStop(_ identifier: DeviceIdentifier) {
    recorder.append(.compatibilityStop(identifier))
  }
}

final class RemappingRouterSink: RemappingSystemInputSink, @unchecked Sendable {
  private let recorder: RemappingRouterRecorder

  init(recorder: RemappingRouterRecorder) { self.recorder = recorder }

  func send(_ action: RemappingSystemInputAction) throws { recorder.append(.system(action)) }
}

final class RemappingRouterForeground: RemappingForegroundApplicationProviding, @unchecked Sendable
{
  private let lock = NSLock()
  private var bundleIdentifier: String?
  private var sequence: [String?] = []
  private var reads = 0

  init(_ bundleIdentifier: String?) { self.bundleIdentifier = bundleIdentifier }

  func frontmostBundleIdentifier() -> String? {
    lock.withLock {
      reads += 1
      guard !sequence.isEmpty else { return bundleIdentifier }
      return sequence.removeFirst()
    }
  }

  func set(_ bundleIdentifier: String?) {
    lock.withLock {
      self.bundleIdentifier = bundleIdentifier
      sequence.removeAll()
    }
  }

  func setSequence(_ values: [String?]) { lock.withLock { sequence = values } }

  func resetReadCount() { lock.withLock { reads = 0 } }

  var readCount: Int { lock.withLock { reads } }

}

final class RemappingRouterAccess: RemappingPostEventAccessProviding, @unchecked Sendable {
  private let lock = NSLock()
  private var state: RemappingPostEventAccessState
  private var sequence: [RemappingPostEventAccessState] = []
  private var reads = 0

  init(_ state: RemappingPostEventAccessState) { self.state = state }

  func currentState() -> RemappingPostEventAccessState {
    lock.withLock {
      reads += 1
      guard !sequence.isEmpty else { return state }
      return sequence.removeFirst()
    }
  }

  func set(_ state: RemappingPostEventAccessState) {
    lock.withLock {
      self.state = state
      sequence.removeAll()
    }
  }

  func setSequence(_ values: [RemappingPostEventAccessState]) {
    lock.withLock { sequence = values }
  }

  func resetReadCount() { lock.withLock { reads = 0 } }

  var readCount: Int { lock.withLock { reads } }
}

final class RemappingTickerClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value: UInt64

  init(_ value: UInt64) { self.value = value }

  func read() -> UInt64 { lock.withLock { value } }

  func advance(by nanoseconds: UInt64) { lock.withLock { value &+= nanoseconds } }
}

final class RemappingTickerProbe: @unchecked Sendable {
  private struct PendingSleep {
    let nanoseconds: UInt64
    let continuation: CheckedContinuation<Void, any Error>
  }

  private let lock = NSLock()
  private let clock: RemappingTickerClock?
  private var pendingSleeps: [PendingSleep] = []
  private var requestedDurations: [UInt64] = []

  init(clock: RemappingTickerClock? = nil) { self.clock = clock }

  var sleepCount: Int { lock.withLock { requestedDurations.count } }

  var sleepDurations: [UInt64] { lock.withLock { requestedDurations } }

  func sleep(nanoseconds: UInt64) async throws {
    try Task.checkCancellation()
    try await withCheckedThrowingContinuation { continuation in
      lock.withLock {
        requestedDurations.append(nanoseconds)
        pendingSleeps.append(PendingSleep(nanoseconds: nanoseconds, continuation: continuation))
      }
    }
    try Task.checkCancellation()
  }

  func resumeNext() {
    let pending = lock.withLock { () -> PendingSleep? in
      guard !pendingSleeps.isEmpty else { return nil }
      return pendingSleeps.removeFirst()
    }
    guard let pending else { return }
    clock?.advance(by: pending.nanoseconds)
    pending.continuation.resume()
  }

  func resumeAll() {
    let sleeps = lock.withLock { () -> [PendingSleep] in
      defer { pendingSleeps.removeAll() }
      return pendingSleeps
    }
    sleeps.forEach { $0.continuation.resume() }
  }
}

struct RemappingRouterHarness {
  let library: RemappingProfileLibrary
  let router: RemappingOutputRouter
  let engine: RemappingEventEngine
  let recorder: RemappingRouterRecorder
  let compatibility: RemappingRouterCompatibility
  let foreground: RemappingRouterForeground
  let access: RemappingRouterAccess
  let fileURL: URL

  static func make(
    profile: RemappingProfile? = nil,
    frontmostBundleIdentifier: String? = "com.example.Game",
    accessState: RemappingPostEventAccessState = .granted,
    tickerIntervalNanoseconds: UInt64? = nil,
    tickerSleeper: @escaping RemappingOutputRouter.TickerSleeper = { _ in },
    uptime: @escaping RemappingOutputRouter.UptimeReader = { 1_000_000_000 },
    compatibilityDispatchCheckpoint: @escaping @Sendable () async -> Void = {},
    compatibilityCheckpointAfterSuppressionCheck: Bool = false,
    systemInputSink: (any RemappingSystemInputSink)? = nil,
    operationCheckpoint: @escaping @Sendable (RemappingRoutingCheckpoint) async -> Void = { _ in }
  ) async throws -> Self {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let fileURL = directory.appendingPathComponent("profiles.json")
    let library = RemappingProfileLibrary(fileURL: fileURL)
    if let profile {
      try await library.create(profile)
      try await library.activate(profileID: profile.id)
    }
    let recorder = RemappingRouterRecorder()
    let foreground = RemappingRouterForeground(frontmostBundleIdentifier)
    let access = RemappingRouterAccess(accessState)
    let sink: any RemappingSystemInputSink =
      systemInputSink ?? RemappingRouterSink(recorder: recorder)
    let engine = RemappingEventEngine(sink: sink)
    let compatibility = RemappingRouterCompatibility(
      recorder: recorder,
      dispatchCheckpoint: compatibilityDispatchCheckpoint,
      checkpointAfterSuppressionCheck: compatibilityCheckpointAfterSuppressionCheck
    )
    let router = RemappingOutputRouter(
      library: library,
      engine: engine,
      compatibility: compatibility,
      foregroundApplication: foreground,
      postEventAccess: access,
      tickerIntervalNanoseconds: tickerIntervalNanoseconds,
      uptime: uptime,
      tickerSleeper: { try await tickerSleeper($0) },
      operationCheckpoint: operationCheckpoint
    )
    return Self(
      library: library,
      router: router,
      engine: engine,
      recorder: recorder,
      compatibility: compatibility,
      foreground: foreground,
      access: access,
      fileURL: fileURL
    )
  }

  func removeFiles() {
    try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
  }
}

func remappingRouterDevice(_ location: UInt32, vendorID: UInt16 = 1118, productID: UInt16 = 654)
  -> DeviceIdentifier
{ DeviceIdentifier(vendorID: vendorID, productID: productID, locationID: location) }

func remappingRouterProfile(
  id: UUID = UUID(),
  name: String = "Game",
  applicationScope: RemappingApplicationScope = .application(bundleIdentifier: "com.example.Game"),
  destination: RemappingDestination = .keyboard(key: .space, modifiers: []),
  turbo: RemappingTurbo? = nil
) -> RemappingProfile {
  RemappingProfile(
    id: id,
    name: name,
    device: RemappingDeviceScope(vendorID: 1118, productID: 654),
    applicationScope: applicationScope,
    bindings: [RemappingBinding(source: .button(.south), destination: destination, turbo: turbo)]
  )
}
