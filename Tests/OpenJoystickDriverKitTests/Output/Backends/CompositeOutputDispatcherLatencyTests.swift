import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct CompositeOutputDispatcherLatencyTests {
  @Test
  func bothModeMirrorsBackendsConcurrently() async {
    let primary = DelayedRecordingDispatcher(delayNanoseconds: 200_000_000)
    let secondary = DelayedRecordingDispatcher(delayNanoseconds: 200_000_000)
    let dispatcher = CompositeOutputDispatcher(
      primary: primary,
      secondary: secondary
    )
    dispatcher.setMode(.both)
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2)
    await dispatcher.dispatch(events: [.buttonPressed(.a)], from: identifier)

    let primaryStart = primary.dispatchStarts.first ?? 0
    let secondaryStart = secondary.dispatchStarts.first ?? 0
    let startDelta = primaryStart >= secondaryStart
      ? primaryStart - secondaryStart : secondaryStart - primaryStart
    #expect(startDelta < 150_000_000)
    #expect(primary.batches == [[.buttonPressed(.a)]])
    #expect(secondary.batches == [[.buttonPressed(.a)]])
  }

  @Test
  func concurrentMirroringPreservesPerBackendBatchOrder() async {
    let primary = DelayedRecordingDispatcher(delayNanoseconds: 5_000_000)
    let secondary = DelayedRecordingDispatcher(delayNanoseconds: 5_000_000)
    let dispatcher = CompositeOutputDispatcher(
      primary: primary,
      secondary: secondary
    )
    dispatcher.setMode(.both)
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2)

    await dispatcher.dispatch(events: [.buttonPressed(.a)], from: identifier)
    await dispatcher.dispatch(events: [.buttonReleased(.a)], from: identifier)

    let expected: [[ControllerEvent]] = [
      [.buttonPressed(.a)],
      [.buttonReleased(.a)],
    ]
    #expect(primary.batches == expected)
    #expect(secondary.batches == expected)
  }
}

private final class DelayedRecordingDispatcher: OutputDispatcher, @unchecked Sendable {
  var suppressOutput = false
  private let delayNanoseconds: UInt64
  private let lock = NSLock()
  private var recordedBatches: [[ControllerEvent]] = []
  private var recordedDispatchStarts: [UInt64] = []

  init(delayNanoseconds: UInt64) {
    self.delayNanoseconds = delayNanoseconds
  }

  var batches: [[ControllerEvent]] {
    lock.withLock { recordedBatches }
  }

  var dispatchStarts: [UInt64] {
    lock.withLock { recordedDispatchStarts }
  }

  func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {
    lock.withLock {
      recordedDispatchStarts.append(DispatchTime.now().uptimeNanoseconds)
    }
    try? await Task.sleep(nanoseconds: delayNanoseconds)
    lock.withLock {
      recordedBatches.append(events)
    }
  }
}
