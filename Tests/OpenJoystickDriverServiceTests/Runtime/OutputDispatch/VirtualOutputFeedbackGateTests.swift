import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

@Suite(.timeLimit(.minutes(1)))
struct VirtualOutputFeedbackGateTests {
  private let controller = LogicalControllerID(vendorID: 1, productID: 2)

  private static func rumble(_ byte: UInt8) -> ControllerOutputCommand {
    .setRumble(RumbleIntensities(lowFrequency: UnipolarValue(byte: byte)), duration: .held)
  }

  /// A gate whose first write waits for `firstWrite`, recording each command when its write
  /// starts.
  private static func gate(
    stallingFirstWriteOn firstWrite: VirtualOutputTransitionGate,
    sent: Locked<[(command: ControllerOutputCommand, at: ContinuousClock.Instant)]>
  ) -> VirtualOutputFeedbackGate {
    VirtualOutputFeedbackGate { _, command in
      let isFirst = sent.withLock { sent -> Bool in
        sent.append((command, .now))
        return sent.count == 1
      }
      if isFirst { await firstWrite.wait() }
    }
  }

  @Test
  func shortCueQueuedBehindABusyWriteReachesTheControllerBeforeItsStop() async {
    // Arrange
    let firstWrite = VirtualOutputTransitionGate()
    let sent = Locked<[(command: ControllerOutputCommand, at: ContinuousClock.Instant)]>([])
    let gate = Self.gate(stallingFirstWriteOn: firstWrite, sent: sent)
    gate.submit(identifier: controller, command: Self.rumble(1))
    await waitUntil("the first write starts") { sent.withLock { !$0.isEmpty } }

    // Act
    gate.submit(identifier: controller, command: Self.rumble(2))
    gate.submit(identifier: controller, command: .stopRumble)
    await firstWrite.open()
    await waitUntil("the stop is sent") { sent.withLock { $0.count >= 3 } }

    // Assert
    #expect(sent.withLock { $0.map(\.command) } == [Self.rumble(1), Self.rumble(2), .stopRumble])
  }

  @Test
  func rumbleThatALaterRumbleReplacesIsDroppedWhileAWriteIsBusy() async {
    // Arrange
    let firstWrite = VirtualOutputTransitionGate()
    let sent = Locked<[(command: ControllerOutputCommand, at: ContinuousClock.Instant)]>([])
    let gate = Self.gate(stallingFirstWriteOn: firstWrite, sent: sent)
    gate.submit(identifier: controller, command: Self.rumble(1))
    await waitUntil("the first write starts") { sent.withLock { !$0.isEmpty } }

    // Act
    for byte: UInt8 in 2...4 { gate.submit(identifier: controller, command: Self.rumble(byte)) }
    await firstWrite.open()
    await waitUntil("the last rumble is sent") { sent.withLock { $0.count >= 2 } }
    gate.submit(identifier: controller, command: .stopRumble)
    await waitUntil("the stop is sent") { sent.withLock { $0.count >= 3 } }

    // Assert
    #expect(sent.withLock { $0.map(\.command) } == [Self.rumble(1), Self.rumble(4), .stopRumble])
  }

  @Test
  func stopAfterADelayedSetWaitsAsLongAsTheHostHeldTheRumble() async throws {
    // Arrange
    let firstWrite = VirtualOutputTransitionGate()
    let sent = Locked<[(command: ControllerOutputCommand, at: ContinuousClock.Instant)]>([])
    let gate = Self.gate(stallingFirstWriteOn: firstWrite, sent: sent)
    gate.submit(identifier: controller, command: Self.rumble(1))
    await waitUntil("the first write starts") { sent.withLock { !$0.isEmpty } }

    // Act: the host holds the cue for 60 ms while the first write is still busy.
    gate.submit(identifier: controller, command: Self.rumble(2))
    try await Task.sleep(for: .milliseconds(60))
    gate.submit(identifier: controller, command: .stopRumble)
    await firstWrite.open()
    await waitUntil("the stop is sent") { sent.withLock { $0.count >= 3 } }

    // Assert
    let writes = sent.withLock { $0 }
    #expect(writes[2].at - writes[1].at >= .milliseconds(55))
  }

  @Test
  func collapsingKeepsCommandsOtherThanRumbleInPlace() {
    // Arrange
    let generation = VirtualOutputFeedbackGeneration(gate: 0, controller: 0)
    let color = ControllerOutputCommand.setRGB(ControllerColor(red: 1, green: 2, blue: 3))
    let entries = [Self.rumble(1), color, Self.rumble(2), .stopRumble].map {
      VirtualOutputFeedbackQueue.Entry(command: $0, generation: generation, arrival: .now)
    }

    // Act
    let collapsed = VirtualOutputFeedbackQueue.collapsed(entries).map(\.command)

    // Assert
    #expect(collapsed == [color, Self.rumble(2), .stopRumble])
  }
}
