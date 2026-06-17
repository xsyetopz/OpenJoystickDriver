import Foundation
@testable import OpenJoystickDriverKit

final class RecordingOutputDispatcher: OutputDispatcher, @unchecked Sendable {
  var suppressOutput = false

  private let lock = NSLock()
  private var recordedBatches: [[ControllerEvent]] = []
  private var recordedStops: [DeviceIdentifier] = []

  var batches: [[ControllerEvent]] {
    lock.withLock { recordedBatches }
  }

  var stoppedIdentifiers: [DeviceIdentifier] {
    lock.withLock { recordedStops }
  }

  var dispatchCount: Int {
    lock.withLock { recordedBatches.count }
  }

  var flattenedEvents: [ControllerEvent] {
    lock.withLock { recordedBatches.flatMap { $0 } }
  }

  // swiftlint:disable:next async_without_await
  func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {
    lock.withLock {
      recordedBatches.append(events)
    }
  }
}

extension RecordingOutputDispatcher: ControllerLifecycleListener {
  func controllerDidStop(_ identifier: DeviceIdentifier) {
    lock.withLock {
      recordedStops.append(identifier)
    }
  }
}

final class NoOpOutputDispatcher: OutputDispatcher, @unchecked Sendable {
  var suppressOutput = false

  // swiftlint:disable:next async_without_await
  func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {}
}
