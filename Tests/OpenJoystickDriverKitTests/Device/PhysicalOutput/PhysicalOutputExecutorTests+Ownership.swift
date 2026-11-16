import Foundation
import Testing

@testable import OpenJoystickDriverKit

private actor EventRecorder {
  private(set) var events: [String] = []
  func append(_ event: String) { events.append(event) }
}

/// Manual stop-rumble, execution-time ownership, dropped channels and queue retirement.
extension PhysicalOutputExecutorTests {
  /// Stop-rumble releases the manual claim, cancels the pending scheduled stop, and writes once.
  @Test
  func stopRumbleCancelsScheduledStopAndWritesOnce() async throws {
    let started = try await startSixaxis(locationID: 524)
    let manager = started.manager
    let rumble = RumbleIntensities(lowFrequency: UnipolarValue(byte: 0x80))
    #expect(await send(.setRumble(rumble, duration: .milliseconds(5_000)), to: started).value)
    #expect(await manager.rumbleStopTasks[started.identifier] != nil)
    let before = await started.backend.recordedOutputReports().count

    let result = await manager.sendControllerOutput(
      .stopRumble,
      for: .model(started.identifier.model)
    )

    #expect(result == ControllerOutputResult(.delivered))
    #expect(await manager.rumbleStopTasks[started.identifier] == nil)
    let written = await started.backend.recordedOutputReports().dropFirst(before).map(sixaxisFields)
    #expect(written.map(\.rumble) == [[0, 0]])
    await manager.stop()
  }

  /// Two effective rumble changes queued behind a running operation: each write reads ownership
  /// when it runs, so neither carries the claim the later change released.
  @Test
  func effectiveRumbleIsReadWhenWriteRuns() async throws {
    let started = try await startSixaxis(locationID: 525)
    let manager = started.manager
    let identifier = started.identifier
    let (queue, release, blocker) = await blockOutputQueue(started)
    let before = await started.backend.recordedOutputReports().count
    let owner = UUID()
    let claim = RemappingPhysicalOutput.rumble(motor: .lowFrequency, intensity: 0.5)
    let on = Task {
      await manager.setMappingPhysicalOutput(claim, active: true, owner: owner, for: identifier)
    }
    await waitForSubmittedOperations(2, on: queue)
    let off = Task {
      await manager.setMappingPhysicalOutput(claim, active: false, owner: owner, for: identifier)
    }
    await waitForSubmittedOperations(3, on: queue)
    await release.open()

    #expect(await blocker.value == .completed(true))
    #expect(await on.value)
    #expect(await off.value)
    let written = await started.backend.recordedOutputReports().dropFirst(before).map(sixaxisFields)
    #expect(written.map(\.rumble) == [[0, 0], [0, 0]])
    await manager.stop()
  }

  /// A partially supported set-rumble drives the channels the controller has and reports the rest.
  @Test
  func partialRumbleReportsDroppedChannels() async throws {
    let started = try await startSixaxis(locationID: 526)
    let rumble = RumbleIntensities(
      lowFrequency: UnipolarValue(byte: 0x80),
      leftTrigger: UnipolarValue(byte: 0x40)
    )
    let result = await started.manager.sendControllerOutput(
      .setRumble(rumble, duration: .held),
      for: .model(started.identifier.model)
    )
    #expect(result == ControllerOutputResult(.delivered, droppedRumbleChannels: [.leftTrigger]))
    let missing = await started.manager.sendControllerOutput(
      .stopRumble,
      for: .model(ControllerModelID(vendorID: 0x1234, productID: 0x5678))
    )
    #expect(missing == ControllerOutputResult(.notFound))
    await started.manager.stop()
  }

  /// An in-process rumble duration outside `0...maxRumbleDurationMs` is an invalid value, and a
  /// command the controller cannot carry is unsupported before its values are checked.
  @Test
  func outOfRangeDurationIsInvalidAfterAdmission() async throws {
    let started = try await startSixaxis(locationID: 532)
    let manager = started.manager
    let rumble = RumbleIntensities(lowFrequency: UnipolarValue(byte: 0x80))
    for milliseconds in [-1, maxRumbleDurationMs + 1] {
      let result = await manager.sendControllerOutput(
        .setRumble(rumble, duration: .milliseconds(milliseconds)),
        for: .model(started.identifier.model)
      )
      #expect(result == ControllerOutputResult(.invalidValue))
    }
    let invalidTrigger = PhysicalAdaptiveTriggerEffect(
      kind: .resistance,
      startPosition: 2,
      strength: 1
    )
    let trigger = await manager.sendControllerOutput(
      .setAdaptiveTrigger(.left, invalidTrigger),
      for: .model(started.identifier.model)
    )
    #expect(trigger == ControllerOutputResult(.unsupportedCapability))
    await manager.stop()
  }

  /// Stopping drains the retired queues and forgets them.
  @Test
  func stopForgetsDrainedRetiredQueues() async throws {
    let started = try await startSixaxis(locationID: 533)
    #expect(await send(.setPlayerIndicator(.player1), to: started).value)
    await started.manager.stop()
    #expect(await started.manager.hidOutputQueues.isEmpty)
    #expect(await started.manager.retiredHIDOutputQueues.isEmpty)
  }

  /// A removed queue's running operation still runs before the interface's next queue starts.
  @Test
  func nextQueueWaitsForRetiredQueueToDrain() async throws {
    let started = try await startSixaxis(locationID: 527)
    let manager = started.manager
    let (queue, release, blocker) = await blockOutputQueue(started)
    await manager.retireOutputQueue(for: started.identifier)
    let fresh = await manager.physicalOutputQueue(for: started.identifier)
    #expect(fresh !== queue)
    let recorder = EventRecorder()
    let next = Task {
      await fresh.perform { _ in
        await recorder.append("next")
        return true
      }
    }
    await waitForSubmittedOperations(1, on: fresh)
    for _ in 0..<100 { await Task.yield() }
    await recorder.append("release")
    await release.open()

    #expect(await blocker.value == .completed(true))
    #expect(await next.value == .completed(true))
    #expect(await recorder.events == ["release", "next"])
    await manager.stop()
  }
}
