import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Failed manual commands withdraw only their own claims, and timed rumble stops.
extension PhysicalOutputExecutorTests {
  func lowFrequency(_ started: Started) async -> RemappingPhysicalOutput? {
    await started.manager.physicalOutputOwnership.effectiveOutput(
      for: .rumble(.lowFrequency),
      device: started.identifier
    )
  }

  /// Queues two manual rumbles behind a running operation, releases the queue, and returns their
  /// outcomes in submission order.
  func sendQueuedRumbles(
    _ first: UInt8,
    _ second: UInt8,
    to started: Started,
    beforeRelease: () async -> Void = {}
  ) async -> [ControllerOutputResult.Outcome] {
    let (queue, release, blocker) = await blockOutputQueue(started)
    let manager = started.manager
    let identifier = started.identifier
    var tasks: [Task<ControllerOutputResult.Outcome, Never>] = []
    for (index, byte) in [first, second].enumerated() {
      tasks.append(
        Task {
          await manager.sendControllerOutput(
            .setRumble(RumbleIntensities(lowFrequency: UnipolarValue(byte: byte)), duration: .held),
            for: .model(identifier.model)
          ).outcome
        }
      )
      await waitForSubmittedOperations(index + 2, on: queue)
    }
    await beforeRelease()
    await release.open()
    #expect(await blocker.value == .completed(true))
    var outcomes: [ControllerOutputResult.Outcome] = []
    for task in tasks { outcomes.append(await task.value) }
    return outcomes
  }

  /// Two manual rumbles that both fail leave no claim behind: the second one's rollback must not
  /// bring back the first one's claim, which would then rumble with no scheduled stop.
  @Test
  func concurrentFailedRumblesLeaveNoClaim() async throws {
    let started = try await startSixaxis(locationID: 528)
    let outcomes = await sendQueuedRumbles(0x40, 0x80, to: started) {
      await started.backend.disableOutputReports()
    }
    #expect(outcomes == [.writeFailed, .writeFailed])
    #expect(await lowFrequency(started) == nil)
    await started.manager.stop()
  }

  /// A failed rumble does not erase a later rumble that was delivered.
  ///
  /// Each write reads the effective claim when it runs, so the first write fails carrying the
  /// second claim.
  @Test
  func failedRumbleKeepsLaterDeliveredClaim() async throws {
    let started = try await startSixaxis(locationID: 529)
    let outcomes = await sendQueuedRumbles(0x40, 0x80, to: started) {
      await started.backend.failNextOutputReports(1)
    }
    #expect(outcomes == [.writeFailed, .delivered])
    #expect(
      await lowFrequency(started) == .rumble(motor: .lowFrequency, intensity: Double(0x80) / 255)
    )
    let written = await started.backend.recordedOutputReports().map(sixaxisFields)
    #expect(written.last?.rumble == [0, 0x80])
    await started.manager.stop()
  }

  /// A failed rumble that was the newest claim writes the effective rumble once more, so the
  /// controller shows the delivered claim it fell back to.
  @Test
  func failedNewestRumbleRewritesEffectiveRumble() async throws {
    let started = try await startSixaxis(locationID: 534)
    let manager = started.manager
    let earlier = RumbleIntensities(lowFrequency: UnipolarValue(byte: 0x40))
    #expect(await send(.setRumble(earlier, duration: .held), to: started).value)
    let (queue, release, blocker) = await blockOutputQueue(started)
    let before = await started.backend.recordedOutputReports().count
    let later = send(
      .setRumble(RumbleIntensities(lowFrequency: UnipolarValue(byte: 0x80)), duration: .held),
      to: started
    )
    await waitForSubmittedOperations(2, on: queue)
    await started.backend.failNextOutputReports(1)
    await release.open()

    #expect(await blocker.value == .completed(true))
    #expect(!(await later.value))
    let written = await started.backend.recordedOutputReports().dropFirst(before).map(sixaxisFields)
    #expect(written.map(\.rumble) == [[0, 0x40]])
    #expect(
      await lowFrequency(started) == .rumble(motor: .lowFrequency, intensity: Double(0x40) / 255)
    )
    await manager.stop()
  }

  /// A failed stop-rumble leaves no manual claim, and a retried stop writes.
  @Test
  func failedStopRumbleLeavesNoClaimAndRetryWrites() async throws {
    let started = try await startSixaxis(locationID: 530)
    let manager = started.manager
    let rumble = RumbleIntensities(lowFrequency: UnipolarValue(byte: 0x80))
    #expect(await send(.setRumble(rumble, duration: .held), to: started).value)
    await started.backend.disableOutputReports()

    let failed = await manager.sendControllerOutput(
      .stopRumble,
      for: .model(started.identifier.model)
    )

    #expect(failed == ControllerOutputResult(.writeFailed))
    #expect(await lowFrequency(started) == nil)
    await started.backend.enableOutputReports()
    let before = await started.backend.recordedOutputReports().count
    let retried = await manager.sendControllerOutput(
      .stopRumble,
      for: .model(started.identifier.model)
    )
    #expect(retried == ControllerOutputResult(.delivered))
    let written = await started.backend.recordedOutputReports().dropFirst(before).map(sixaxisFields)
    #expect(written.map(\.rumble) == [[0, 0]])
    await manager.stop()
  }

  /// A timed rumble's scheduled stop fires after its duration and writes the stop.
  @Test
  func timedRumbleStopsAfterItsDuration() async throws {
    let started = try await startSixaxis(locationID: 531)
    let manager = started.manager
    let rumble = RumbleIntensities(lowFrequency: UnipolarValue(byte: 0x80))
    #expect(await send(.setRumble(rumble, duration: .milliseconds(20)), to: started).value)
    let stop = try #require(await manager.rumbleStopTasks[started.identifier])
    let before = await started.backend.recordedOutputReports().count

    await stop.value

    let written = await started.backend.recordedOutputReports().dropFirst(before).map(sixaxisFields)
    #expect(written.map(\.rumble) == [[0, 0]])
    #expect(await lowFrequency(started) == nil)
    #expect(await manager.rumbleStopTasks[started.identifier] == nil)
    await manager.stop()
  }
}
