import Foundation
import Testing

@testable import OpenJoystickDriverService

struct SystemPowerNotificationObserverTests {
  @Test
  func deliversSleepAndWakeInFIFOOrderToOneAsyncHandler() async {
    let center = FakePowerSource()
    let recorder = PowerNotificationRecorder(blockWillSleep: true)
    let observer = SystemPowerNotificationObserver(powerSource: center) { event in
      await recorder.receive(event)
    }

    observer.start()
    observer.start()
    center.send(.systemWillSleep(notificationID: 7))
    await recorder.waitForEventCount(1)
    await recorder.waitForSleepHandlerSuspended()
    center.send(.systemHasPoweredOn)

    try? await Task.sleep(for: .milliseconds(20))
    #expect(await recorder.events == [.willSleep])

    await recorder.resumeWillSleep()
    await recorder.waitForEventCount(2)
    #expect(await recorder.events == [.willSleep, .didWake])
    await observer.stop()
  }

  @Test
  func stopJoinsInFlightHandlerAndDropsBufferedEvents() async {
    let center = FakePowerSource()
    let recorder = PowerNotificationRecorder(blockWillSleep: true)
    let observer = SystemPowerNotificationObserver(powerSource: center) { event in
      await recorder.receive(event)
    }

    observer.start()
    center.send(.systemWillSleep(notificationID: 7))
    await recorder.waitForEventCount(1)
    await recorder.waitForSleepHandlerSuspended()
    center.send(.systemHasPoweredOn)

    let completion = StopCompletionRecorder()
    let firstStop = Task {
      await observer.stop()
      await completion.recordReturn()
    }
    let secondStop = Task {
      await observer.stop()
      await completion.recordReturn()
    }
    await recorder.waitForHandlerCancellation()

    #expect(await completion.returnCount == 0)
    #expect(await recorder.events == [.willSleep])

    await recorder.resumeWillSleep()
    await firstStop.value
    await secondStop.value
    #expect(await completion.returnCount == 2)
    #expect(await recorder.events == [.willSleep])
  }

  @Test
  func stopRemovesObserversAndIsIdempotent() async {
    let center = FakePowerSource()
    let recorder = PowerNotificationRecorder(blockWillSleep: false)
    let observer = SystemPowerNotificationObserver(powerSource: center) { event in
      await recorder.receive(event)
    }

    observer.start()
    center.send(.systemHasPoweredOn)
    await recorder.waitForEventCount(1)

    await observer.stop()
    await observer.stop()
    center.send(.systemWillSleep(notificationID: 7))
    observer.start()
    try? await Task.sleep(for: .milliseconds(20))

    #expect(await recorder.events == [.didWake])
  }

  @Test
  func acknowledgesSleepOnceAfterTeardownReturns() async {
    let source = FakePowerSource()
    let recorder = PowerNotificationRecorder(blockWillSleep: true)
    let observer = SystemPowerNotificationObserver(powerSource: source) { event in
      await recorder.receive(event)
    }

    observer.start()
    source.send(.systemWillSleep(notificationID: 7))
    await recorder.waitForSleepHandlerSuspended()
    source.send(.systemHasPoweredOn)
    try? await Task.sleep(for: .milliseconds(20))
    #expect(source.acknowledgements.isEmpty)

    await recorder.resumeWillSleep()
    await source.waitForAcknowledgements(1)
    await recorder.waitForEventCount(2)
    try? await Task.sleep(for: .milliseconds(20))
    #expect(source.acknowledgements == [7])
    #expect(await recorder.events == [.willSleep, .didWake])
    await observer.stop()
  }

  @Test
  func allowsIdleSleepAtOnceWithoutEvent() async {
    let source = FakePowerSource()
    let recorder = PowerNotificationRecorder(blockWillSleep: false)
    let observer = SystemPowerNotificationObserver(powerSource: source) { event in
      await recorder.receive(event)
    }

    observer.start()
    source.send(.canSystemSleep(notificationID: 3))
    #expect(source.acknowledgements == [3])
    #expect(await recorder.events.isEmpty)
    await observer.stop()
  }

  @Test
  func stopAcknowledgesInFlightSleepOnceAfterHandlerReturns() async {
    let source = FakePowerSource()
    let recorder = PowerNotificationRecorder(blockWillSleep: true)
    let observer = SystemPowerNotificationObserver(powerSource: source) { event in
      await recorder.receive(event)
    }

    observer.start()
    source.send(.systemWillSleep(notificationID: 7))
    await recorder.waitForSleepHandlerSuspended()
    let stop = Task { await observer.stop() }
    await recorder.waitForHandlerCancellation()
    #expect(source.acknowledgements.isEmpty)

    await recorder.resumeWillSleep()
    await stop.value
    #expect(source.acknowledgements == [7])
    #expect(source.stopCount == 1)
  }
}

private final class FakePowerSource: SystemPowerSource, @unchecked Sendable {
  private let lock = NSLock()
  private var onMessage: (@Sendable (SystemPowerMessage) -> Void)?
  private var storedAcknowledgements: [Int] = []
  private var storedStopCount = 0

  var acknowledgements: [Int] { lock.withLock { storedAcknowledgements } }
  var stopCount: Int { lock.withLock { storedStopCount } }

  func start(onMessage: @escaping @Sendable (SystemPowerMessage) -> Void) {
    lock.withLock { self.onMessage = onMessage }
  }

  func allowPowerChange(notificationID: Int) {
    lock.withLock { storedAcknowledgements.append(notificationID) }
  }

  func stop() {
    lock.withLock {
      onMessage = nil
      storedStopCount += 1
    }
  }

  func send(_ message: SystemPowerMessage) {
    let onMessage = lock.withLock { self.onMessage }
    onMessage?(message)
  }

  func waitForAcknowledgements(_ count: Int) async {
    for _ in 0..<200 where acknowledgements.count < count {
      try? await Task.sleep(for: .milliseconds(10))
    }
  }
}

private actor PowerNotificationRecorder {
  private let blockWillSleep: Bool
  private var storedEvents: [SystemPowerNotificationObserver.Event] = []
  private var eventCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
  private var sleepContinuation: CheckedContinuation<Void, Never>?
  private var sleepGateReady = false
  private var sleepGateWaiter: CheckedContinuation<Void, Never>?
  private var handlerCancellationObserved = false
  private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []

  init(blockWillSleep: Bool) { self.blockWillSleep = blockWillSleep }

  var events: [SystemPowerNotificationObserver.Event] { storedEvents }

  func receive(_ event: SystemPowerNotificationObserver.Event) async {
    storedEvents.append(event)
    let ready = eventCountWaiters.filter { $0.0 <= storedEvents.count }
    eventCountWaiters.removeAll { $0.0 <= storedEvents.count }
    for (_, continuation) in ready { continuation.resume() }
    if blockWillSleep, event == .willSleep {
      await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
          sleepContinuation = continuation
          sleepGateReady = true
          sleepGateWaiter?.resume()
          sleepGateWaiter = nil
        }
      } onCancel: {
        Task { await self.recordHandlerCancellation() }
      }
    }
  }

  func waitForEventCount(_ count: Int) async {
    guard storedEvents.count < count else { return }
    await withCheckedContinuation { eventCountWaiters.append((count, $0)) }
  }

  func waitForSleepHandlerSuspended() async {
    guard !sleepGateReady else { return }
    await withCheckedContinuation { sleepGateWaiter = $0 }
  }

  func waitForHandlerCancellation() async {
    guard !handlerCancellationObserved else { return }
    await withCheckedContinuation { cancellationWaiters.append($0) }
  }

  private func recordHandlerCancellation() {
    handlerCancellationObserved = true
    for continuation in cancellationWaiters { continuation.resume() }
    cancellationWaiters.removeAll()
  }

  func resumeWillSleep() {
    sleepContinuation?.resume()
    sleepContinuation = nil
  }
}

private actor StopCompletionRecorder {
  private(set) var returnCount = 0

  func recordReturn() { returnCount += 1 }
}
