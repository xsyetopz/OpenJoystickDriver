import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

@Suite(.serialized) struct RemappingRouterReentrancyTests {
  @Test func beginWaitsForCompatibilityDispatchAdmittedBeforeSuppression() async throws {
    let gate = RoutingCheckpointGate(pausing: .dispatch)
    let harness = try await RemappingRouterHarness.make(
      profile: remappingRouterProfile(applicationScope: .global),
      compatibilityDispatchCheckpoint: { await gate.checkpoint(.dispatch) },
      compatibilityCheckpointAfterSuppressionCheck: true
    )
    defer {
      gate.resume()
      harness.removeFiles()
    }
    let compatibility = remappingRouterDevice(1, vendorID: 1356, productID: 2508)
    try await harness.router.dispatchCausally(events: [], from: compatibility)
    harness.recorder.removeAll()
    await gate.arm()

    let dispatch = Task {
      try await harness.router.dispatchCausally(events: [.buttonPressed(.b)], from: compatibility)
    }
    await gate.waitUntilPaused()
    let completion = AsyncCompletionProbe()
    let begin = Task {
      let transaction = try await harness.router.beginProfileTransaction()
      await completion.finish()
      return transaction
    }
    #expect(await eventually { harness.compatibility.suppressOutput })
    #expect(!(await completion.isFinished))

    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: compatibility)
    try await harness.router.tick(at: 1_100_000_000)
    #expect(harness.recorder.snapshot().isEmpty)

    let competingBegin = Task { try await harness.router.beginProfileTransaction() }
    await #expect(throws: RemappingOutputRoutingError.profileTransactionAlreadyActive) {
      try await competingBegin.value
    }

    gate.resume()
    try await dispatch.value
    let transaction = try await begin.value
    #expect(
      harness.recorder.snapshot() == [
        .compatibility([.buttonPressed(.b)], compatibility), .compatibilityStop(compatibility)
      ]
    )

    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: compatibility)
    #expect(harness.recorder.snapshot().count == 2)
    try await harness.router.rollBackProfileTransaction(transaction)
  }

  @Test func transactionAdmissionStopsAlreadySuspendedCompatibilityDispatch() async throws {
    let gate = RoutingCheckpointGate(pausing: .dispatch)
    let checkpointHook: @Sendable () async -> Void = { await gate.checkpoint(.dispatch) }
    let harness = try await RemappingRouterHarness.make(
      profile: remappingRouterProfile(applicationScope: .global),
      compatibilityDispatchCheckpoint: checkpointHook
    )
    defer {
      gate.resume()
      harness.removeFiles()
    }
    let compatibility = remappingRouterDevice(1, vendorID: 1356, productID: 2508)
    await gate.arm()

    let dispatch = Task {
      try await harness.router.dispatchCausally(events: [.buttonPressed(.b)], from: compatibility)
    }
    await gate.waitUntilPaused()
    let begin = Task { try await harness.router.beginProfileTransaction() }
    #expect(await eventually { harness.compatibility.suppressOutput })
    gate.resume()

    try await dispatch.value
    let transaction = try await begin.value
    #expect(
      !harness.recorder.snapshot().contains(.compatibility([.buttonPressed(.b)], compatibility))
    )
    try await harness.router.rollBackProfileTransaction(transaction)
  }

  @Test func transactionAdmissionClosesQueuedWindowAfterOuterApply() async throws {
    let gate = RoutingCheckpointGate(pausing: .apply)
    let harness = try await makeHarness(gate: gate)
    defer {
      gate.resume()
      harness.removeFiles()
    }
    let device = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(events: [], from: device)
    harness.recorder.removeAll()
    await gate.arm()

    let dispatch = Task {
      try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: device)
    }
    await gate.waitUntilPaused()
    let begin = Task { try await harness.router.beginProfileTransaction() }
    #expect(await eventually { harness.compatibility.suppressOutput })
    gate.resume()

    try await dispatch.value
    let transaction = try await begin.value
    #expect(!harness.recorder.snapshot().contains(.system(.keyDown(.space))))
    try await harness.router.rollBackProfileTransaction(transaction)
  }

  @Test func transactionAdmissionInvalidatesDispatchPausedBeforeEngineHop() async throws {
    let gate = RoutingCheckpointGate(pausing: .dispatch)
    let harness = try await makeHarness(gate: gate)
    defer {
      gate.resume()
      harness.removeFiles()
    }
    let device = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(events: [], from: device)
    harness.recorder.removeAll()
    await gate.arm()

    let dispatch = Task {
      try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: device)
    }
    await gate.waitUntilPaused()
    let begin = Task { try await harness.router.beginProfileTransaction() }
    #expect(await eventually { harness.compatibility.suppressOutput })
    gate.resume()

    try await dispatch.value
    let transaction = try await begin.value
    #expect(!harness.recorder.snapshot().contains(.system(.keyDown(.space))))
    try await harness.router.rollBackProfileTransaction(transaction)
  }

  @Test func transactionAdmissionInvalidatesTickPausedBeforeEngineHop() async throws {
    let gate = RoutingCheckpointGate(pausing: .tick)
    let harness = try await makeHarness(
      gate: gate,
      profile: remappingRouterProfile(
        applicationScope: .global,
        turbo: RemappingTurbo(repeatRateHz: 10, dutyCycle: 0.25)
      )
    )
    defer {
      gate.resume()
      harness.removeFiles()
    }
    let device = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: device)
    harness.recorder.removeAll()
    await gate.arm()

    let tick = Task { try await harness.router.tick(at: 1_100_000_000) }
    await gate.waitUntilPaused()
    let begin = Task { try await harness.router.beginProfileTransaction() }
    #expect(await eventually { harness.compatibility.suppressOutput })
    gate.resume()

    try await tick.value
    let transaction = try await begin.value
    #expect(harness.recorder.snapshot() == [.system(.keyUp(.space))])
    try await harness.router.rollBackProfileTransaction(transaction)
  }

  @Test func shutdownInvalidatesDispatchPausedBeforeEngineHop() async throws {
    let gate = RoutingCheckpointGate(pausing: .dispatch)
    let harness = try await makeHarness(gate: gate)
    defer {
      gate.resume()
      harness.removeFiles()
    }
    let device = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(events: [], from: device)
    harness.recorder.removeAll()
    await gate.arm()

    let dispatch = Task {
      try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: device)
    }
    await gate.waitUntilPaused()
    let shutdown = Task { try await harness.router.shutdown() }
    #expect(await eventually { harness.engine.emissionBarrier.isTerminated })
    gate.resume()

    try? await dispatch.value
    try await shutdown.value
    #expect(!harness.recorder.snapshot().contains(.system(.keyDown(.space))))
    #expect(harness.compatibility.suppressOutput)
    await #expect(throws: RemappingOutputRoutingError.shutDown) {
      try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: device)
    }
  }

  @Test func shutdownWaitsForCompatibilityDispatchAdmittedBeforeSuppression() async throws {
    let gate = RoutingCheckpointGate(pausing: .dispatch)
    let harness = try await RemappingRouterHarness.make(
      profile: remappingRouterProfile(applicationScope: .global),
      compatibilityDispatchCheckpoint: { await gate.checkpoint(.dispatch) },
      compatibilityCheckpointAfterSuppressionCheck: true
    )
    defer {
      gate.resume()
      harness.removeFiles()
    }
    let compatibility = remappingRouterDevice(1, vendorID: 1356, productID: 2508)
    try await harness.router.dispatchCausally(events: [], from: compatibility)
    harness.recorder.removeAll()
    await gate.arm()

    let dispatch = Task {
      try await harness.router.dispatchCausally(events: [.buttonPressed(.b)], from: compatibility)
    }
    await gate.waitUntilPaused()
    let completion = AsyncCompletionProbe()
    let shutdown = Task {
      try await harness.router.shutdown()
      await completion.finish()
    }
    #expect(await eventually { harness.engine.emissionBarrier.isTerminated })
    #expect(harness.compatibility.suppressOutput)
    #expect(!(await completion.isFinished))

    gate.resume()
    try await dispatch.value
    try await shutdown.value
    #expect(
      harness.recorder.snapshot() == [
        .compatibility([.buttonPressed(.b)], compatibility), .compatibilityStop(compatibility)
      ]
    )
    await #expect(throws: RemappingOutputRoutingError.shutDown) {
      try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: compatibility)
    }
    #expect(harness.recorder.snapshot().count == 2)
  }

  @Test func concurrentShutdownCallersJoinOneInProgressCleanup() async throws {
    let sink = BlockingReleaseSink()
    let harness = try await RemappingRouterHarness.make(
      profile: remappingRouterProfile(applicationScope: .global),
      systemInputSink: sink
    )
    defer {
      sink.resumeRelease()
      harness.removeFiles()
    }
    let device = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: device)
    let firstCompletion = AsyncCompletionProbe()
    let secondCompletion = AsyncCompletionProbe()

    let first = Task {
      try await harness.router.shutdown()
      await firstCompletion.finish()
    }
    await sink.waitUntilReleaseIsBlocked()
    let second = Task {
      try await harness.router.shutdown()
      await secondCompletion.finish()
    }
    for _ in 0..<100 { await Task.yield() }
    #expect(!(await firstCompletion.isFinished))
    #expect(!(await secondCompletion.isFinished))

    sink.resumeRelease()
    try await first.value
    try await second.value
    #expect(sink.actions == [.keyDown(.space), .keyUp(.space)])
  }

  @Test func failedTerminalCleanupRetriesWithoutReopeningOutput() async throws {
    let sink = TransientTerminalFailureSink(failingCalls: [2, 3])
    let harness = try await RemappingRouterHarness.make(
      profile: remappingRouterProfile(applicationScope: .global),
      systemInputSink: sink
    )
    defer { harness.removeFiles() }
    let device = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: device)

    await #expect(throws: RemappingOutputRoutingError.engine(.sinkUnavailable)) {
      try await harness.router.shutdown()
    }
    await #expect(throws: RemappingOutputRoutingError.shutDown) {
      try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: device)
    }

    try await harness.router.shutdown()
    try await harness.router.shutdown()
    #expect(sink.actions == [.keyDown(.space), .keyUp(.space)])
    await #expect(throws: RemappingOutputRoutingError.shutDown) {
      try await harness.router.tick(at: 2_000_000_000)
    }
  }

  @Test(arguments: [TransactionCompletion.accept, .rollBack])
  func shutdownPreventsPausedCompletionFromInstallingOrReopeningRoutes(
    _ completion: TransactionCompletion
  ) async throws {
    let gate = RoutingCheckpointGate(pausing: .installRoutes)
    let harness = try await makeHarness(gate: gate)
    defer {
      gate.resume()
      harness.removeFiles()
    }
    let device = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(events: [], from: device)
    let transaction = try await harness.router.beginProfileTransaction()
    await gate.arm()

    let completionTask = Task {
      switch completion {
      case .accept: try await harness.router.acceptProfileTransaction(transaction)
      case .rollBack: try await harness.router.rollBackProfileTransaction(transaction)
      }
    }
    await gate.waitUntilPaused()
    let shutdown = Task { try await harness.router.shutdown() }
    #expect(await eventually { harness.engine.emissionBarrier.isTerminated })
    gate.resume()

    await #expect(throws: RemappingOutputRoutingError.shutDown) { try await completionTask.value }
    try await shutdown.value
    #expect(await harness.router.statuses().isEmpty)
    #expect(harness.compatibility.suppressOutput)
  }

  @Test func shutdownPreventsPausedRecoveryFromInstallingOrReopeningRoutes() async throws {
    let gate = RoutingCheckpointGate(pausing: .installRoutes)
    let harness = try await makeHarness(gate: gate)
    defer {
      gate.resume()
      harness.removeFiles()
    }
    let device = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(events: [], from: device)
    let transaction = try await harness.router.beginProfileTransaction()
    await harness.router.markProfileTransactionUnreconciled(transaction, detail: "test")
    await gate.arm()

    let recovery = Task { try await harness.router.recoverProfileTransaction() }
    await gate.waitUntilPaused()
    let shutdown = Task { try await harness.router.shutdown() }
    #expect(await eventually { harness.engine.emissionBarrier.isTerminated })
    gate.resume()

    await #expect(throws: RemappingOutputRoutingError.shutDown) { try await recovery.value }
    try await shutdown.value
    #expect(await harness.router.statuses().isEmpty)
    #expect(harness.compatibility.suppressOutput)
  }

  private func makeHarness(
    gate: RoutingCheckpointGate,
    profile: RemappingProfile = remappingRouterProfile(applicationScope: .global)
  ) async throws -> RemappingRouterHarness {
    let checkpointHook: @Sendable (RemappingRoutingCheckpoint) async -> Void = { checkpoint in
      await gate.checkpoint(checkpoint)
    }
    return try await RemappingRouterHarness.make(
      profile: profile,
      operationCheckpoint: checkpointHook
    )
  }
}
