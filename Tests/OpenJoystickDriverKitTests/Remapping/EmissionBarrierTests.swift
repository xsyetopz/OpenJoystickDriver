import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingEmissionBarrierTests {
  @Test func transactionAdmissionWaitsForAlreadyAdmittedLeaseAndRejectsNewWork() async throws {
    let barrier = RemappingEmissionBarrier()
    let lease = try #require(barrier.acquireLease())
    let owner = UUID()
    let completion = BarrierCompletionProbe()

    let suspension = Task {
      let admission = await barrier.suspend(owner: owner)
      await completion.finish()
      return admission
    }
    while barrier.currentPermit() != nil { await Task.yield() }

    #expect(barrier.acquireLease() == nil)
    #expect(!(await completion.isFinished))
    lease.finish()

    guard case .admitted(let permit) = await suspension.value else {
      Issue.record("Expected the first transaction owner to be admitted.")
      return
    }
    #expect(barrier.permits(permit))
  }

  @Test func sinkCanQueryBarrierWithoutRecursiveLocking() async throws {
    let barrier = RemappingEmissionBarrier()
    let sink = BarrierQueryingSink()
    sink.barrier = barrier
    let engine = RemappingEventEngine(sink: sink, emissionBarrier: barrier)

    try await engine.process(events: [.buttonPressed(.a)], from: device(), using: profile(), at: 1)
    await barrier.terminate()
    try await engine.drainAfterTermination()

    #expect(sink.actions == [.keyDown(.space), .keyUp(.space)])
  }

  @Test func completedTransactionPermanentlyInvalidatesPreviouslyAdmittedWork() async throws {
    let sink = RemappingTestSink()
    let barrier = RemappingEmissionBarrier()
    let engine = RemappingEventEngine(sink: sink, emissionBarrier: barrier)
    let stalePermit = try #require(barrier.currentPermit())
    let transaction = UUID()

    let admission = await barrier.suspend(owner: transaction)
    guard case .admitted(let transactionPermit) = admission else {
      Issue.record("Expected transaction admission.")
      return
    }
    #expect(barrier.resume(owner: transaction))

    await #expect(throws: RemappingEventEngineError.outputSuspended) {
      try await engine.process(
        events: [.buttonPressed(.a)],
        from: device(),
        using: profile(),
        at: 1,
        requiring: stalePermit
      )
    }
    await #expect(throws: RemappingEventEngineError.outputSuspended) {
      try await engine.setProfile(profile(), for: device(), requiring: transactionPermit)
    }
    await #expect(throws: RemappingEventEngineError.outputSuspended) {
      try await engine.recover(requiring: transactionPermit)
    }
    #expect(sink.actions().isEmpty)

    let currentPermit = try #require(barrier.currentPermit())
    try await engine.process(
      events: [.buttonPressed(.a)],
      from: device(),
      using: profile(),
      at: 2,
      requiring: currentPermit
    )
    #expect(sink.actions() == [.keyDown(.space)])
  }

  @Test func terminationAllowsOneDrainAndRejectsEveryLaterEngineMutation() async throws {
    let sink = RemappingTestSink()
    let barrier = RemappingEmissionBarrier()
    let engine = RemappingEventEngine(sink: sink, emissionBarrier: barrier)
    let admitted = try #require(barrier.currentPermit())
    try await engine.process(
      events: [.buttonPressed(.a)],
      from: device(),
      using: profile(),
      at: 1,
      requiring: admitted
    )

    await barrier.terminate()
    try await engine.drainAfterTermination()
    try await engine.drainAfterTermination()

    await #expect(throws: RemappingEventEngineError.outputSuspended) {
      try await engine.process(
        events: [.buttonPressed(.a)],
        from: device(),
        using: profile(),
        at: 2,
        requiring: admitted
      )
    }
    await #expect(throws: RemappingEventEngineError.outputSuspended) {
      try await engine.tick(at: 3, requiring: admitted)
    }
    await #expect(throws: RemappingEventEngineError.outputSuspended) {
      try await engine.releaseAll(for: device(), requiring: admitted)
    }
    #expect(sink.actions() == [.keyDown(.space), .keyUp(.space)])
  }

  private func device() -> DeviceIdentifier {
    DeviceIdentifier(vendorID: 1, productID: 2, locationID: 3)
  }

  private func profile() -> RemappingProfile {
    RemappingProfile(
      name: "Barrier",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [
        RemappingBinding(
          source: .button(.south),
          destination: .keyboard(key: .space, modifiers: [])
        ),
      ]
    )
  }
}

private actor BarrierCompletionProbe {
  private(set) var isFinished = false

  func finish() { isFinished = true }
}

private final class BarrierQueryingSink: RemappingSystemInputSink, @unchecked Sendable {
  private let lock = NSLock()
  private var recordedActions: [RemappingSystemInputAction] = []
  var barrier: RemappingEmissionBarrier?

  var actions: [RemappingSystemInputAction] { lock.withLock { recordedActions } }

  func send(_ action: RemappingSystemInputAction) throws {
    _ = barrier?.currentPermit()
    _ = barrier?.isTerminated
    lock.withLock { recordedActions.append(action) }
  }
}
