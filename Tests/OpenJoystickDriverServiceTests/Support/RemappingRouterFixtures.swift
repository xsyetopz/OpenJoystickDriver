import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport

@testable import OpenJoystickDriverService

enum RemappingRouterTrace: Equatable {
  case virtualGamepad(ControllerState, LogicalControllerID)
  case virtualOutputActivation(LogicalControllerID)
  case virtualOutputStop(LogicalControllerID)
  case system(RemappingSystemInputAction)
  case gamepad(RemappingGamepadState, LogicalControllerID)
}

final class RemappingRouterRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var entries: [RemappingRouterTrace] = []

  func append(_ entry: RemappingRouterTrace) { lock.withLock { entries.append(entry) } }

  func snapshot() -> [RemappingRouterTrace] { lock.withLock { entries } }

  func removeAll() { lock.withLock { entries.removeAll() } }
}

final class RemappingRouterVirtualOutput: OutputDispatcher, ControllerLifecycleListener,
  RemappingGamepadSink, RemappingGamepadOutputControlling, @unchecked Sendable
{
  private let lock = NSLock()
  private let recorder: RemappingRouterRecorder
  private let dispatchCheckpoint: @Sendable () async -> Void
  private let checkpointAfterSuppressionCheck: Bool
  private var suppressed = false
  private var remappingSuppressed = false
  private var rejectsNeutral = false
  var rejectNeutral: Bool {
    get { lock.withLock { rejectsNeutral } }
    set { lock.withLock { rejectsNeutral = newValue } }
  }

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

  func dispatch(
    _ event: ControllerEvent,
    from identifier: LogicalControllerID
  ) async { await record(.virtualGamepad(event.state, identifier)) }

  /// Calls `onPublished` once the report is recorded, as a virtual device does once it has it.
  func dispatchPublishing(
    _ event: ControllerEvent,
    from identifier: LogicalControllerID,
    onPublished: @escaping @Sendable () -> Void
  ) async throws {
    if await record(.virtualGamepad(event.state, identifier)) { onPublished() }
  }

  func activateOutput(for identifier: LogicalControllerID) async {
    await record(.virtualOutputActivation(identifier))
  }

  /// Records `trace` unless output is suppressed; true when it recorded.
  @discardableResult
  private func record(_ trace: RemappingRouterTrace) async -> Bool {
    if checkpointAfterSuppressionCheck {
      guard !suppressOutput else { return false }
      await dispatchCheckpoint()
      recorder.append(trace)
      return true
    }
    await dispatchCheckpoint()
    await Task.yield()
    guard !suppressOutput else { return false }
    recorder.append(trace)
    return true
  }

  func setRemappingOutputSuppressed(_ suppressed: Bool) {
    lock.withLock { remappingSuppressed = suppressed }
  }

  func send(_ state: RemappingGamepadState, for identifier: LogicalControllerID) throws {
    guard state == .neutral || !lock.withLock({ remappingSuppressed }) else {
      throw CancellationError()
    }
    if state == .neutral, rejectNeutral { throw CancellationError() }
    recorder.append(.gamepad(state, identifier))
  }

  func controllerDidStop(_ identifier: LogicalControllerID) {
    recorder.append(.virtualOutputStop(identifier))
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
  private var appID: String?
  private var sequence: [String?] = []
  private var reads = 0

  init(_ appID: String?) { self.appID = appID }

  func frontmostAppID() -> String? {
    lock.withLock {
      reads += 1
      guard !sequence.isEmpty else { return appID }
      return sequence.removeFirst()
    }
  }

  func set(_ appID: String?) {
    lock.withLock {
      self.appID = appID
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
    for sleep in sleeps { sleep.continuation.resume() }
  }
}

struct RemappingRouterHarness {
  let library: RemappingProfileLibrary
  let router: RemappingOutputRouter
  let engine: RemappingEventEngine
  let recorder: RemappingRouterRecorder
  let virtualOutput: RemappingRouterVirtualOutput
  let foreground: RemappingRouterForeground
  let access: RemappingRouterAccess
  let directory: URL

  static func make(
    profile: RemappingProfile? = nil,
    frontmostAppID: String? = "com.example.Game",
    accessState: RemappingPostEventAccessState = .granted,
    tickerIntervalNanoseconds: UInt64? = nil,
    tickerSleeper: @escaping RemappingOutputRouter.TickerSleeper = { _ in },
    uptime: @escaping RemappingOutputRouter.UptimeReader = { 1_000_000_000 },
    virtualOutputDispatchCheckpoint: @escaping @Sendable () async -> Void = {},
    virtualOutputCheckpointAfterSuppressionCheck: Bool = false,
    systemInputSink: (any RemappingSystemInputSink)? = nil,
    operationCheckpoint: @escaping @Sendable (RemappingRoutingCheckpoint) async -> Void = { _ in }
  ) async throws -> Self {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let library = RemappingProfileLibrary(directory: directory)
    if let profile {
      try await library.create(profile)
      try await library.activate(profileID: profile.id)
    }
    let recorder = RemappingRouterRecorder()
    let foreground = RemappingRouterForeground(frontmostAppID)
    let access = RemappingRouterAccess(accessState)
    let sink: any RemappingSystemInputSink =
      systemInputSink ?? RemappingRouterSink(recorder: recorder)
    let virtualOutput = RemappingRouterVirtualOutput(
      recorder: recorder,
      dispatchCheckpoint: virtualOutputDispatchCheckpoint,
      checkpointAfterSuppressionCheck: virtualOutputCheckpointAfterSuppressionCheck
    )
    let engine = RemappingEventEngine(sink: sink, gamepadSink: virtualOutput)
    let router = RemappingOutputRouter(
      library: library,
      engine: engine,
      virtualOutput: virtualOutput,
      foregroundApplication: foreground,
      postEventAccess: access,
      installationKey: testPortKeyInstallationKey,
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
      virtualOutput: virtualOutput,
      foreground: foreground,
      access: access,
      directory: directory
    )
  }

  func removeFiles() {
    try? FileManager.default.removeItem(at: directory)
  }
}

/// Every file under a profile library directory, keyed by its path relative to the directory.
func libraryFiles(in directory: URL) throws -> [String: Data] {
  let manager = FileManager.default
  var files: [String: Data] = [:]
  for path in try manager.subpathsOfDirectory(atPath: directory.path) {
    let url = directory.appendingPathComponent(path)
    var isDirectory: ObjCBool = false
    if manager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue {
      files[path] = try Data(contentsOf: url)
    }
  }
  return files
}

func remappingRouterDevice(
  _ location: UInt32,
  vendorID: UInt16 = 1118,
  productID: UInt16 = 654
) -> LogicalControllerID {
  LogicalControllerID(vendorID: vendorID, productID: productID, locationID: location)
}

/// The session token the coordinator harnesses report for `device`.
func remappingRouterToken(_ device: LogicalControllerID) -> ControllerSessionToken {
  let identity = device.hardware
  return .fixture(
    String(
      format: "%04X%04X%08X",
      identity.model.vendorID,
      identity.model.productID,
      device.address?.locationID ?? 0
    )
  )
}

/// The controllers the coordinator harnesses report as connected: the default model at locations
/// 1 and 2, and a left and a right Joy-Con at locations 1 and 2.
@Sendable
func remappingRouterConnectedControllers() -> [ConnectedController] {
  [
    remappingRouterDevice(1),
    remappingRouterDevice(2),
    remappingRouterDevice(1, vendorID: 0x057E, productID: 0x2006),
    remappingRouterDevice(2, vendorID: 0x057E, productID: 0x2007),
  ].map {
    ConnectedController(
      logicalControllerID: $0,
      sessionToken: remappingRouterToken($0),
      installationKey: testPortKeyInstallationKey
    )
  }
}

func remappingRouterProfile(
  id: UUID = UUID(),
  name: String = "Game",
  applicationScope: RemappingApplicationScope = .application(appIDs: ["com.example.Game"]),
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
