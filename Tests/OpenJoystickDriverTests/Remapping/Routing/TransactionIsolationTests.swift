import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

@Suite(.serialized) struct RemappingProfileTransactionIsolationTests {
  @Test func rejectedCandidateCannotEmitBeforeExactRollbackCompletes() async throws {
    let original = transactionProfile(name: "Original", key: .space)
    let gate = ResponseAcceptanceGate()
    let harness = try await TransactionIsolationHarness.make(
      initialProfile: original,
      maximumResponseBytes: 1
    ) { _ in await gate.pause() }
    defer { harness.removeFiles() }
    let mapped = remappingRouterDevice(1)
    let newlyConnected = remappingRouterDevice(2)
    let compatibility = remappingRouterDevice(3, vendorID: 1356, productID: 2508)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: mapped)
    try await harness.router.dispatchCausally(events: [], from: compatibility)
    harness.recorder.removeAll()
    let exactPriorBytes = try Data(contentsOf: harness.fileURL)
    let candidate = transactionProfile(
      id: original.id,
      name: original.name,
      key: .b,
      includesContinuousPointer: true
    )

    let mutation = Task { await harness.coordinator.update(candidate, expectedCurrent: original) }
    await gate.waitUntilPaused()
    try await harness.router.dispatchCausally(
      events: [.buttonPressed(.a), .rightStickChanged(x: 0.75, y: 0)],
      from: mapped
    )
    try await harness.router.tick(at: 1_100_000_000)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: newlyConnected)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.b)], from: compatibility)

    let gatedTrace = harness.recorder.snapshot()
    #expect(gatedTrace.count == 2)
    #expect(gatedTrace.filter { $0 == .compatibilityStop(compatibility) }.count == 1)
    #expect(gatedTrace.filter { $0 == .system(.keyUp(.space)) }.count == 1)
    #expect(!gatedTrace.contains(.system(.keyDown(.b))))
    #expect(!gatedTrace.contains(.system(.mouseMoved(axis: .x, amount: 0.75))))
    #expect(!gatedTrace.contains(.compatibility([.buttonPressed(.b)], compatibility)))
    gate.resume()
    let result = await mutation.value

    guard case .failure(let error) = result else {
      Issue.record("Expected response-size rollback.")
      return
    }
    #expect(error.code == .responseTooLarge)
    #expect(try Data(contentsOf: harness.fileURL) == exactPriorBytes)
    #expect(try await harness.library.profile(id: original.id) == original)
    #expect(await harness.router.status(for: mapped)?.activeProfileID == original.id)
    #expect(await harness.router.status(for: newlyConnected)?.activeProfileID == original.id)

    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: mapped)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.b)], from: compatibility)
    let resumedTrace = harness.recorder.snapshot()
    #expect(resumedTrace.count == 4)
    #expect(resumedTrace.contains(.system(.keyDown(.space))))
    #expect(resumedTrace.contains(.compatibility([.buttonPressed(.b)], compatibility)))
  }

  @Test func acceptedCandidateCannotEmitUntilResponseAcceptanceCompletes() async throws {
    let original = transactionProfile(name: "Original", key: .space)
    let gate = ResponseAcceptanceGate()
    let harness = try await TransactionIsolationHarness.make(initialProfile: original) { _ in
      await gate.pause()
    }
    defer { harness.removeFiles() }
    let mapped = remappingRouterDevice(1)
    let compatibility = remappingRouterDevice(2, vendorID: 1356, productID: 2508)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: mapped)
    try await harness.router.dispatchCausally(events: [], from: compatibility)
    let candidate = transactionProfile(id: original.id, name: original.name, key: .b)

    let mutation = Task { await harness.coordinator.update(candidate, expectedCurrent: original) }
    await gate.waitUntilPaused()
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: mapped)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.b)], from: compatibility)
    #expect(!harness.recorder.snapshot().contains(.system(.keyDown(.b))))
    #expect(
      !harness.recorder.snapshot().contains(.compatibility([.buttonPressed(.b)], compatibility))
    )

    gate.resume()
    let snapshot = try await mutation.value.get()
    #expect(snapshot.profiles == [candidate])
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: mapped)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.b)], from: compatibility)
    #expect(harness.recorder.snapshot().contains(.system(.keyDown(.b))))
    #expect(
      harness.recorder.snapshot().contains(.compatibility([.buttonPressed(.b)], compatibility))
    )
  }

  @Test func createFailureRollsBackGateAndRestoresOutput() async throws {
    let original = transactionProfile(name: "Original", key: .space)
    let harness = try await TransactionIsolationHarness.make(initialProfile: original)
    defer { harness.removeFiles() }
    let mapped = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: mapped)
    let exactPriorBytes = try Data(contentsOf: harness.fileURL)

    let result = await harness.coordinator.create(original)

    guard case .failure(let error) = result else {
      Issue.record("Expected duplicate create failure.")
      return
    }
    #expect(error.code == .profileAlreadyExists)
    #expect(try Data(contentsOf: harness.fileURL) == exactPriorBytes)
    #expect(harness.recorder.snapshot() == [.system(.keyDown(.space)), .system(.keyUp(.space))])
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: mapped)
    #expect(harness.recorder.snapshot().last == .system(.keyDown(.space)))
  }

  @Test func failedRestoreRemainsTypedFailClosedUntilExplicitRecovery() async throws {
    let original = transactionProfile(name: "Original", key: .space)
    let gate = ResponseAcceptanceGate()
    let harness = try await TransactionIsolationHarness.make(
      initialProfile: original,
      maximumResponseBytes: 1
    ) { _ in await gate.pause() }
    defer { harness.removeFiles() }
    let mapped = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: mapped)
    let checkpoint = try await harness.library.checkpoint()
    let candidate = transactionProfile(id: original.id, name: original.name, key: .b)

    let mutation = Task { await harness.coordinator.update(candidate, expectedCurrent: original) }
    await gate.waitUntilPaused()
    let parent = harness.fileURL.deletingLastPathComponent()
    try FileManager.default.removeItem(at: harness.fileURL)
    try FileManager.default.removeItem(at: parent)
    try Data("blocks-directory-restoration".utf8).write(to: parent)
    gate.resume()
    let result = await mutation.value

    guard case .failure(let error) = result else {
      Issue.record("Expected unreconciled rollback failure.")
      return
    }
    #expect(error.code == .transactionUnreconciled)
    let status = try #require(await harness.router.status(for: mapped))
    #expect(status.eligibility == .unavailable)
    guard case .profileTransactionUnreconciled = status.error else {
      Issue.record("Expected typed unreconciled route status.")
      return
    }
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: mapped)
    #expect(!harness.recorder.snapshot().contains(.system(.keyDown(.b))))

    try FileManager.default.removeItem(at: parent)
    try await harness.library.restore(checkpoint)
    try await harness.router.recoverProfileTransaction()
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: mapped)
    #expect(harness.recorder.snapshot().last == .system(.keyDown(.space)))
  }

  @Test func coordinatorSnapshotUsesOneRouterAccessSample() async throws {
    let probe = MutablePostEventProbe()
    let harness = try await TransactionIsolationHarness.make(
      initialProfile: transactionProfile(name: "Original", key: .space),
      accessProbe: probe
    )
    defer { harness.removeFiles() }
    let mapped = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(events: [], from: mapped)
    probe.setPreflight([true, false])

    let snapshot = try await harness.coordinator.snapshot().get()

    #expect(probe.preflightCount == 1)
    #expect(snapshot.postEventAccess == .granted)
    #expect(snapshot.routes.count == 1)
    #expect(snapshot.routes[0].postEventAccess == .granted)
    #expect(snapshot.routes[0].eligibility == .eligible)
  }

  @Test func cancelledMutationRollsBackBeforeNextSerializedMutationRuns() async throws {
    let original = transactionProfile(name: "Original", key: .space)
    let gate = ResponseAcceptanceGate()
    let harness = try await TransactionIsolationHarness.make(initialProfile: original) { _ in
      await gate.pause()
    }
    defer { harness.removeFiles() }
    let firstCandidate = transactionProfile(id: original.id, name: original.name, key: .b)
    let finalCandidate = transactionProfile(id: original.id, name: original.name, key: .c)

    let first = Task { await harness.coordinator.update(firstCandidate, expectedCurrent: original) }
    await gate.waitUntilPaused()
    let second = Task {
      await harness.coordinator.update(finalCandidate, expectedCurrent: original)
    }
    first.cancel()
    gate.resume()

    guard case .failure(let cancellation) = await first.value else {
      Issue.record("Expected cancelled mutation failure.")
      return
    }
    #expect(cancellation.code == .unexpected)
    let finalSnapshot = try await second.value.get()
    #expect(finalSnapshot.profiles == [finalCandidate])
    #expect(try await harness.library.profile(id: original.id) == finalCandidate)
    let mapped = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: mapped)
    #expect(harness.recorder.snapshot().last == .system(.keyDown(.c)))
  }
}

private struct TransactionIsolationHarness {
  let fileURL: URL
  let library: RemappingProfileLibrary
  let router: RemappingOutputRouter
  let coordinator: RemappingRequestCoordinator
  let recorder: RemappingRouterRecorder

  static func make(
    initialProfile: RemappingProfile,
    maximumResponseBytes: Int = ApplicationServiceRemappingRPC.maximumPayloadBytes,
    accessProbe: MutablePostEventProbe = MutablePostEventProbe(),
    responseHook: @escaping RemappingRequestCoordinator.MutationResponseAcceptanceHook = { _ in }
  ) async throws -> Self {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let fileURL = directory.appendingPathComponent("profiles.json")
    let library = RemappingProfileLibrary(fileURL: fileURL)
    try await library.create(initialProfile)
    try await library.activate(profileID: initialProfile.id)
    let recorder = RemappingRouterRecorder()
    let access = CoreGraphicsPostEventAccess(probe: accessProbe)
    let router = RemappingOutputRouter(
      library: library,
      engine: RemappingEventEngine(sink: RemappingRouterSink(recorder: recorder)),
      compatibility: RemappingRouterCompatibility(recorder: recorder),
      foregroundApplication: RemappingRouterForeground("com.example.Game"),
      postEventAccess: access,
      tickerIntervalNanoseconds: nil
    ) { 1_000_000_000 }
    return Self(
      fileURL: fileURL,
      library: library,
      router: router,
      coordinator: RemappingRequestCoordinator(
        library: library,
        router: router,
        postEventAccess: access,
        maximumResponseBytes: maximumResponseBytes,
        beforeMutationResponseAcceptance: responseHook
      ),
      recorder: recorder
    )
  }

  func removeFiles() {
    let parent = fileURL.deletingLastPathComponent()
    try? FileManager.default.removeItem(at: parent)
  }
}

private actor ResponseAcceptanceGate {
  private var paused = false
  private var didPause = false
  private var continuation: CheckedContinuation<Void, Never>?

  func pause() async {
    guard !didPause else { return }
    didPause = true
    paused = true
    await withCheckedContinuation { continuation = $0 }
  }

  func waitUntilPaused() async { while !paused { await Task.yield() } }

  nonisolated func resume() { Task { await release() } }

  private func release() {
    continuation?.resume()
    continuation = nil
  }
}

private final class MutablePostEventProbe: CoreGraphicsPostEventAccessProbing, @unchecked Sendable {
  private let lock = NSLock()
  private var preflightValues = [true]
  private var index = 0

  var preflightCount: Int { lock.withLock { index } }

  func setPreflight(_ values: [Bool]) {
    lock.withLock {
      preflightValues = values
      index = 0
    }
  }

  func preflight() -> Bool {
    lock.withLock {
      defer { index += 1 }
      return preflightValues[min(index, preflightValues.count - 1)]
    }
  }

  func request() -> Bool { preflight() }
}

private func transactionProfile(
  id: UUID = UUID(),
  name: String,
  key: RemappingKeyboardKey,
  includesContinuousPointer: Bool = false
) -> RemappingProfile {
  var bindings = [
    RemappingBinding(source: .button(.south), destination: .keyboard(key: key, modifiers: []))
  ]
  if includesContinuousPointer {
    bindings.append(
      RemappingBinding(
        source: .axis(.rightStickX),
        destination: .mouseMovement(.x),
        axisTuning: RemappingAxisTuning(deadzone: 0, gain: 1)
      )
    )
  }
  return RemappingProfile(
    id: id,
    name: name,
    device: RemappingDeviceScope(vendorID: 1118, productID: 654),
    applicationScope: .application(bundleIdentifier: "com.example.Game"),
    bindings: bindings
  )
}
