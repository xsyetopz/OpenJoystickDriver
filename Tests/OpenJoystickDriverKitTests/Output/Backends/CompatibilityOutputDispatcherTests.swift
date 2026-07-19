import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct CompatibilityOutputDispatcherTests {
  @Test func dispatchesOnlyToCurrentCompatibilityBackend() async {
    let previous = RecordingCompatibilityDispatcher()
    let current = RecordingCompatibilityDispatcher()
    let dispatcher = CompatibilityOutputDispatcher()
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2)

    dispatcher.setBackend(previous)
    dispatcher.setBackend(current)
    await dispatcher.dispatch(events: [.buttonPressed(.a)], from: identifier)

    #expect(previous.batches.isEmpty)
    #expect(current.batches == [[.buttonPressed(.a)]])
  }

  @Test func explicitSuppressionStopsCompatibilityDispatch() async {
    let backend = RecordingCompatibilityDispatcher()
    let dispatcher = CompatibilityOutputDispatcher()
    dispatcher.setBackend(backend)
    dispatcher.suppressOutput = true

    await dispatcher.dispatch(
      events: [.buttonPressed(.a)],
      from: DeviceIdentifier(vendorID: 1, productID: 2)
    )

    #expect(backend.batches.isEmpty)
    #expect(backend.suppressOutput)
  }
}

private final class RecordingCompatibilityDispatcher: OutputDispatcher, @unchecked Sendable {
  var suppressOutput = false
  private let lock = NSLock()
  private var recordedBatches: [[ControllerEvent]] = []

  var batches: [[ControllerEvent]] { lock.withLock { recordedBatches } }

  func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {
    await Task.yield()
    lock.withLock { recordedBatches.append(events) }
  }
}
