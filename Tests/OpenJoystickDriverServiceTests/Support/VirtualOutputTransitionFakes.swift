import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

actor VirtualOutputTransitionGate {
  private var opened = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    if opened { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func open() {
    opened = true
    let pending = waiters
    waiters.removeAll()
    for continuation in pending { continuation.resume() }
  }
}

actor VirtualOutputFeedbackProbe {
  private var commands: [ControllerOutputCommand] = []

  func append(_ command: ControllerOutputCommand) { commands.append(command) }
  func count() -> Int { commands.count }
  func values() -> [ControllerOutputCommand] { commands }
}

final class VirtualOutputTransitionProbe: VirtualOutputDispatching,
  VirtualOutputControllerActivating, @unchecked Sendable
{
  struct ActivationFailure: Error, Sendable {}

  let activationGate: VirtualOutputTransitionGate?
  let failsActivation: Bool
  private let lock = NSLock()
  private var closeCount = 0
  private var activations: [[DeviceIdentifier]] = []

  init(activationGate: VirtualOutputTransitionGate? = nil, failsActivation: Bool = false) {
    self.activationGate = activationGate
    self.failsActivation = failsActivation
  }

  var closeCountValue: Int { lock.withLock { closeCount } }
  var activationValues: [[DeviceIdentifier]] { lock.withLock { activations } }
  var suppressOutput = false
  var status: VirtualOutputBackendStatus { .backend("probe") }
  var lastRumbleStatus: String? { nil }

  func activate(for identifiers: [DeviceIdentifier]) async throws {
    lock.withLock { activations.append(identifiers) }
    await activationGate?.wait()
    if failsActivation { throw ActivationFailure() }
  }

  func activate(controller identifier: DeviceIdentifier) async throws {
    try await activate(for: [identifier])
  }

  func dispatch(_: ControllerEvent, labels _: ControllerButtonLabels, from _: DeviceIdentifier) {}
  func activateOutput(for _: DeviceIdentifier) {}
  func setOutputSuppressed(_ suppressed: Bool) { suppressOutput = suppressed }
  func close() { lock.withLock { closeCount += 1 } }
}

final class VirtualOutputTransitionFactory: @unchecked Sendable {
  struct BuildFailure: Error, Sendable {}

  private let lock = NSLock()
  private var probes: [VirtualOutputTransitionProbe] = []
  private var failsBuild = false
  private var failsActivation = false
  private var gate: VirtualOutputTransitionGate?

  var buildFails: Bool {
    get { lock.withLock { failsBuild } }
    set { lock.withLock { failsBuild = newValue } }
  }
  var activationFails: Bool {
    get { lock.withLock { failsActivation } }
    set { lock.withLock { failsActivation = newValue } }
  }
  var firstActivationGate: VirtualOutputTransitionGate? {
    get { lock.withLock { gate } }
    set { lock.withLock { gate = newValue } }
  }

  func make() throws -> any VirtualOutputDispatching {
    try lock.withLock { () throws -> VirtualOutputTransitionProbe in
      if failsBuild { throw BuildFailure() }
      let probe = VirtualOutputTransitionProbe(
        activationGate: probes.isEmpty ? gate : nil,
        failsActivation: failsActivation
      )
      probes.append(probe)
      return probe
    }
  }

  func values() -> [VirtualOutputTransitionProbe] { lock.withLock { probes } }

  func waitForCount(_ count: Int) async {
    while lock.withLock({ probes.count }) < count { await Task.yield() }
  }
}

/// A server with no live output whose backends come from `factory`, over isolated defaults.
struct VirtualOutputTransitionFixture {
  let server: ApplicationServiceServer
  let defaults: UserDefaults
  let suiteName: String
  /// Empty and removed by `tearDown`, so no test reads the user's personas.
  let personaDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent(
      "OpenJoystickDriverTests.Personas.\(UUID().uuidString)",
      isDirectory: true
    )

  init(
    factory: VirtualOutputTransitionFactory,
    identifiers: [DeviceIdentifier],
    timeouts: VirtualOutputTransitionTimeouts = .standard,
    clock: VirtualOutputTransitionClock = .system
  ) throws {
    suiteName = "OpenJoystickDriverTests.VirtualOutputTransition.\(UUID().uuidString)"
    defaults = try #require(UserDefaults(suiteName: suiteName))
    let virtualOutputDispatcher = VirtualOutputRouter()
    let profileLibrary = RemappingProfileLibrary()
    let postEventAccess = CoreGraphicsPostEventAccess()
    let remappingRouter = RemappingOutputRouter(
      library: profileLibrary,
      engine: RemappingEventEngine(sink: CoreGraphicsSystemInputSink(access: postEventAccess)),
      virtualOutput: virtualOutputDispatcher,
      foregroundApplication: WorkspaceRemappingForegroundApplication(),
      postEventAccess: postEventAccess
    )
    server = ApplicationServiceServer(
      deviceManager: DeviceManager(dispatcher: remappingRouter),
      permissionManager: PermissionManager(),
      dispatcher: virtualOutputDispatcher,
      remappingProfileLibrary: profileLibrary,
      remappingRouter: remappingRouter,
      postEventAccess: postEventAccess,
      userSpaceDispatcherFactory: { _ in try factory.make() },
      connectedIdentifierProvider: { identifiers },
      virtualOutputTransitionTimeouts: timeouts,
      virtualOutputTransitionClock: clock,
      defaults: defaults,
      personaDirectory: personaDirectory
    )
  }

  /// Installs `backend` as the live output, as a successful earlier activation would.
  func installLive(_ backend: VirtualOutputTransitionProbe) {
    server.userSpaceLock.withLock {
      server.userSpaceDispatcher = backend
      server.userSpaceCloseSlot = VirtualOutputBackendCloseSlot(backend)
      server.userSpaceEnabled = true
      server.userSpaceStatus = backend.status
      server.dispatcher.setBackend(backend)
    }
  }

  func tearDown() async {
    await server.stop()
    defaults.removePersistentDomain(forName: suiteName)
    try? FileManager.default.removeItem(at: personaDirectory)
  }
}
