import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// The per-interface output executor: each command encodes and writes as one queue operation, so
/// a stateful encoder's reports reach the controller in encode order.
@Suite(.timeLimit(.minutes(2)))
struct PhysicalOutputExecutorTests {
  struct Started {
    let backend: ScriptedHIDAccessBackend
    let manager: DeviceManager
    let connection: HIDDeviceConnection
    let identifier: LogicalControllerID
  }

  /// Connects a USB Sixaxis, whose report 0x01 carries rumble and LEDs from stored state.
  func startSixaxis(locationID: UInt32, productID: UInt16 = 0x0268) async throws -> Started {
    let backend = ScriptedHIDAccessBackend()
    await backend.enableOutputReports()
    await backend.enableFeatureReports()
    let connection = HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: 0x054C,
        productID: productID,
        productName: "Executor controller",
        transportProperty: "USB",
        physicalLocationIdentifier: locationID,
        interfaces: [gamepadHIDInterface(host: .usb)]
      ),
      routingAddress: .ioKit(locationID: locationID, interfaceNumber: nil)
    )
    await backend.setConnectionSnapshots([
      HIDDeviceConnectionSnapshot(connection: connection, ownership: .exclusive)
    ])
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: backend)
    )
    await manager.markStartedForTest()
    await manager.handleHIDEvent(.connected(connection: connection, ownership: .exclusive))
    let identifier = try #require(await manager.pipelines.keys.first)
    return Started(
      backend: backend,
      manager: manager,
      connection: connection,
      identifier: identifier
    )
  }

  /// The rumble bytes and the LED byte of a Sixaxis report 0x01.
  func sixaxisFields(_ report: PhysicalHIDOutputReport) -> (rumble: [UInt8], led: UInt8) {
    ([report.bytes[3], report.bytes[5]], report.bytes[10])
  }

  /// Concurrent rumble and player commands, each changing one field, at mixed priorities while
  /// other requests contend for the manager.
  ///
  /// Written in encode order, every report differs from the one before it in at most that one
  /// field; a report written out of encode order carries a later command's field without an earlier
  /// one's.
  @Test
  func concurrentStatefulCommandsWriteInEncodeOrder() async throws {
    let started = try await startSixaxis(locationID: 520)
    let manager = started.manager
    let identifier = started.identifier
    let players: [PhysicalPlayerIndicator] = [.player1, .player2, .player3, .player4]
    var violations: [String] = []
    for iteration in 0..<400 {
      let before = await started.backend.recordedOutputReports().count
      let commands: [ControllerOutputCommand] = (0..<8).map { index in
        guard index.isMultiple(of: 2) else { return .setPlayerIndicator(players[index / 2]) }
        let level = UnipolarValue(byte: UInt8(1 + (iteration * 4 + index / 2) % 250))
        return .setRumble(
          RumbleIntensities(lowFrequency: level, leftHaptic: level),
          duration: .held
        )
      }
      await withTaskGroup(of: Bool.self) { group in
        for _ in 0..<16 {
          group.addTask(priority: .high) {
            _ = await manager.controllerState(for: .model(identifier.model))
            return true
          }
        }
        for (index, command) in commands.enumerated() {
          let priority: TaskPriority = index.isMultiple(of: 3) ? .utility : .high
          group.addTask(priority: priority) {
            await manager.sendOutputForTest(command, for: identifier)
          }
        }
        for await delivered in group where !delivered { violations.append("undelivered") }
      }
      let reports = await started.backend.recordedOutputReports()
      let written = Array(reports[max(before - 1, 0)...])
      #expect(written.count == commands.count + (before > 0 ? 1 : 0))
      for (previous, next) in zip(written, written.dropFirst()) {
        let changed =
          (sixaxisFields(previous).rumble != sixaxisFields(next).rumble ? 1 : 0)
          + (sixaxisFields(previous).led != sixaxisFields(next).led ? 1 : 0)
        if changed > 1 { violations.append("iteration \(iteration): \(changed) fields changed") }
      }
    }
    await manager.stop()
    #expect(violations.isEmpty, "\(violations)")
  }

  /// Holds the controller's output queue with a running operation until `release` opens.
  func blockOutputQueue(
    _ started: Started
  ) async -> (
    queue: PhysicalHIDOutputSerialQueue, release: StartupTestGate,
    blocker: Task<PhysicalOutputQueueOutcome<Bool>, Never>
  ) {
    let manager = started.manager
    let queue =
      await manager.outputQueueForTest(for: started.identifier) ?? PhysicalHIDOutputSerialQueue()
    await manager.installOutputQueueForTest(queue, for: started.identifier)
    let blockerStarted = StartupTestGate()
    let release = StartupTestGate()
    let blocker = Task {
      await queue.perform { _ in
        await blockerStarted.open()
        await release.wait()
        return true
      }
    }
    await blockerStarted.wait()
    return (queue, release, blocker)
  }

  func waitForSubmittedOperations(_ count: Int, on queue: PhysicalHIDOutputSerialQueue) async {
    await waitUntil("\(count) operations are submitted") {
      await queue.submittedOperationCount >= count
    }
  }

  func send(_ command: ControllerOutputCommand, to started: Started) -> Task<Bool, Never> {
    Task {
      await started.manager.sendOutputForTest(
        command,
        for: started.identifier
      )
    }
  }

  /// Queued commands that `cancelAll()` drops neither write nor advance the encoder, so the
  /// neutralization queued after the cancel writes the stored state without them.
  @Test
  func cancelAllDropsQueuedCommandsBeforeNeutralization() async throws {
    let started = try await startSixaxis(locationID: 521)
    let manager = started.manager
    let pipeline = try #require(await manager.pipelines[started.identifier])
    #expect(await send(.setPlayerIndicator(.player1), to: started).value)
    let (queue, release, blocker) = await blockOutputQueue(started)
    let before = await started.backend.recordedOutputReports().count
    let player = send(.setPlayerIndicator(.player2), to: started)
    let rumble = send(
      .setRumble(RumbleIntensities(lowFrequency: UnipolarValue(byte: 0x80)), duration: .held),
      to: started
    )
    await waitForSubmittedOperations(3, on: queue)
    queue.cancelAll()
    let neutralization = Task {
      await manager.neutralizePhysicalOutputs(for: started.identifier, pipeline: pipeline)
    }
    await waitForSubmittedOperations(4, on: queue)
    await release.open()

    #expect(await blocker.value == .completed(true))
    #expect(!(await player.value))
    #expect(!(await rumble.value))
    await neutralization.value
    let written = await started.backend.recordedOutputReports().dropFirst(before).map(sixaxisFields)
    #expect(written.map(\.rumble) == [[0, 0], [0, 0]])
    #expect(written.map(\.led) == [0x02, 0x20])
    await manager.stop()
  }

  /// A physical disconnect cancels everything queued, here a pending command and a probe
  /// operation, before it queues the detached neutralization, and the failed command does not
  /// restore claims for the gone controller.
  @Test
  func disconnectCancelsPendingUserOutput() async throws {
    let started = try await startSixaxis(locationID: 522)
    #expect(await send(.setPlayerIndicator(.player1), to: started).value)
    let (queue, release, blocker) = await blockOutputQueue(started)
    let before = await started.backend.recordedOutputReports().count
    let player = send(.setPlayerIndicator(.player2), to: started)
    await waitForSubmittedOperations(2, on: queue)
    let probe = Task { await queue.perform { _ in true } }
    await waitForSubmittedOperations(3, on: queue)
    let disconnect = Task {
      await started.manager.handleHIDEvent(.disconnected(connection: started.connection))
    }
    await waitForSubmittedOperations(4, on: queue)
    await release.open()

    #expect(await blocker.value == .completed(true))
    #expect(await probe.value == .cancelled)
    #expect(!(await player.value))
    await disconnect.value
    let written = await started.backend.recordedOutputReports().dropFirst(before).map(sixaxisFields)
    #expect(written.map(\.led) == [0x02, 0x20])
    let ownership = await started.manager.physicalOutputOwnership
    #expect(ownership.effectiveOutput(for: .playerIndicator, device: started.identifier) == nil)
    await started.manager.stop()
  }

  /// System sleep tears down every controller; everything queued, here a pending command and a
  /// probe operation, is canceled before the teardown neutralization.
  @Test
  func sleepCancelsPendingUserOutput() async throws {
    let started = try await startSixaxis(locationID: 523)
    #expect(await send(.setPlayerIndicator(.player1), to: started).value)
    let (queue, release, blocker) = await blockOutputQueue(started)
    let before = await started.backend.recordedOutputReports().count
    let player = send(.setPlayerIndicator(.player2), to: started)
    await waitForSubmittedOperations(2, on: queue)
    let probe = Task { await queue.perform { _ in true } }
    await waitForSubmittedOperations(3, on: queue)
    let sleep = Task { await started.manager.systemWillSleep() }
    await waitForSubmittedOperations(4, on: queue)
    await release.open()

    #expect(await blocker.value == .completed(true))
    #expect(await probe.value == .cancelled)
    #expect(!(await player.value))
    await sleep.value
    let written = await started.backend.recordedOutputReports().dropFirst(before).map(sixaxisFields)
    #expect(written.map(\.led) == [0x02, 0x20])
    await started.manager.stop()
  }
}
