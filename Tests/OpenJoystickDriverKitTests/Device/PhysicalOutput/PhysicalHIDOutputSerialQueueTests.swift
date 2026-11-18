import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

private actor PhysicalHIDOutputOrderRecorder {
  private var values: [Int] = []
  private var firstValueWaiters: [CheckedContinuation<Void, Never>] = []

  func append(_ value: Int) {
    values.append(value)
    if value == 1 {
      for waiter in firstValueWaiters { waiter.resume() }
      firstValueWaiters.removeAll()
    }
  }

  func waitForFirstValue() async {
    if values.contains(1) { return }
    await withCheckedContinuation { firstValueWaiters.append($0) }
  }

  func snapshot() -> [Int] { values }
}

@Suite(.timeLimit(.minutes(2)))
struct PhysicalHIDOutputSerialQueueTests {
  /// An operation runs at the queue's own priority, whatever the caller's, on a queue and on a
  /// queue created after another.
  @Test
  func operationsRunAtQueuePriorityWhateverCallerPriority() async {
    let queue = PhysicalHIDOutputSerialQueue()
    let outcome = await Task(priority: .utility) {
      await queue.perform { _ in Task.currentPriority }
    }.value
    #expect(outcome == .completed(PhysicalHIDOutputSerialQueue.taskPriority))
    let successor = PhysicalHIDOutputSerialQueue(after: queue)
    let successorOutcome = await Task(priority: .utility) {
      await successor.perform { _ in Task.currentPriority }
    }.value
    #expect(successorOutcome == .completed(PhysicalHIDOutputSerialQueue.taskPriority))
  }

  @Test
  func commandsCompleteInSubmissionOrderWithoutInterleaving() async {
    let queue = PhysicalHIDOutputSerialQueue()
    let recorder = PhysicalHIDOutputOrderRecorder()

    let first = Task {
      await queue.perform { _ in
        await recorder.append(1)
        await Task.yield()
        await recorder.append(2)
        return true
      }
    }
    await recorder.waitForFirstValue()
    let second = Task {
      await queue.perform { _ in
        await recorder.append(3)
        return true
      }
    }

    #expect(await first.value == .completed(true))
    #expect(await second.value == .completed(true))
    #expect(await recorder.snapshot() == [1, 2, 3])
  }

  @Test
  func cancelAllDropsQueuedOperationsAndRunsLaterOnes() async {
    let queue = PhysicalHIDOutputSerialQueue()
    let recorder = PhysicalHIDOutputOrderRecorder()
    let started = StartupTestGate()
    let release = StartupTestGate()
    let running = Task {
      await queue.perform { _ in
        await started.open()
        await release.wait()
        await recorder.append(1)
        return true
      }
    }
    await started.wait()
    let queued = Task {
      await queue.perform { _ in
        await recorder.append(2)
        return true
      }
    }
    await waitUntil("two operations are submitted") {
      await queue.submittedOperationCount >= 2
    }
    queue.cancelAll()
    let later = Task {
      await queue.perform { _ in
        await recorder.append(3)
        return true
      }
    }
    await waitUntil("three operations are submitted") {
      await queue.submittedOperationCount >= 3
    }
    await release.open()

    #expect(await running.value == .completed(true))
    #expect(await queued.value == .cancelled)
    #expect(await later.value == .completed(true))
    #expect(await recorder.snapshot() == [1, 3])
  }
}
