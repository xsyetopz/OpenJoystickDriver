import Foundation
import Testing

@testable import OpenJoystickDriverKit

private actor UserSpaceDispatcherTestGate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var waiting = false

  func wait() async {
    if isOpen { return }
    waiting = true
    await withCheckedContinuation { waiters.append($0) }
  }

  func waitUntilWaiting() async { while !waiting && !isOpen { await Task.yield() } }

  func open() {
    isOpen = true
    let pending = waiters
    waiters.removeAll()
    for continuation in pending { continuation.resume() }
  }
}

private final class UserSpaceDispatcherTestBackend: UserSpaceOutputDispatcher.VirtualDeviceBackend,
  @unchecked Sendable
{
  struct SendFailure: Error, Sendable {}

  private let lock = NSLock()
  private var closed = false
  private(set) var closeCount = 0
  private(set) var sendCount = 0
  private var reports: [[UInt8]] = []
  let sendGate: UserSpaceDispatcherTestGate?
  let failsSend: Bool

  init(sendGate: UserSpaceDispatcherTestGate? = nil, failsSend: Bool = false) {
    self.sendGate = sendGate
    self.failsSend = failsSend
  }

  func send(_ report: [UInt8]) async throws {
    await sendGate?.wait()
    if failsSend { throw SendFailure() }
    guard lock.withLock({ !closed }) else { return }
    lock.withLock {
      sendCount += 1
      reports.append(report)
    }
  }

  func close() {
    lock.withLock {
      guard !closed else { return }
      closed = true
      closeCount += 1
    }
  }

  func counts() -> (close: Int, send: Int) { lock.withLock { (closeCount, sendCount) } }
  func publishedReports() -> [[UInt8]] { lock.withLock { reports } }
}

struct UserSpaceOutputDispatcherLifecycleTests {
  @Test func neutralRetryAfterRetirementDoesNotCreateAnotherDevice() async throws {
    let creations = LockedCounter()
    let dispatcher = UserSpaceOutputDispatcher { _ in
      _ = creations.next()
      return UserSpaceDispatcherTestBackend()
    }
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2)
    try await dispatcher.send(.neutral, for: identifier)
    #expect(creations.current() == 0)
    try await dispatcher.send(RemappingGamepadState(buttons: [.south]), for: identifier)
    await dispatcher.controllerDidStop(identifier)
    try await dispatcher.send(.neutral, for: identifier)
    #expect(creations.current() == 1)
    await dispatcher.close()
  }

  @Test func remappedReportsAndKeepaliveUseTheirOwnSuppressionGate() async throws {
    let backend = UserSpaceDispatcherTestBackend()
    let dispatcher = UserSpaceOutputDispatcher { _ in backend }
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2)
    await dispatcher.setOutputSuppressed(true)
    await dispatcher.dispatch(events: [.buttonPressed(.a)], from: identifier)
    #expect(backend.publishedReports().isEmpty)
    try await dispatcher.send(RemappingGamepadState(buttons: [.north]), for: identifier)
    let pressed = try #require(backend.publishedReports().last)
    let initialCount = backend.counts().send
    let deadline = ContinuousClock.now.advanced(by: .milliseconds(250))
    while backend.counts().send == initialCount, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(8))
    }
    #expect(backend.counts().send > initialCount)
    #expect(backend.publishedReports().last == pressed)
    await dispatcher.setRemappingOutputSuppressed(true)
    await #expect(throws: CancellationError.self) {
      try await dispatcher.send(RemappingGamepadState(buttons: [.south]), for: identifier)
    }
    try await dispatcher.send(.neutral, for: identifier)
    #expect(
      backend.publishedReports().last
        == OJDGenericGamepadFormat().buildInputReport(from: VirtualGamepadState())
    )
    await dispatcher.close()
  }

  @Test func remappedStatePreservesSmallAxesAndDistinctShareThenReplacesHeldState() async throws {
    let backend = UserSpaceDispatcherTestBackend()
    let dispatcher = UserSpaceOutputDispatcher { _ in backend }
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2)
    try await dispatcher.send(
      RemappingGamepadState(buttons: [.share], axes: [.leftStickX: 0.01]), for: identifier
    )
    var expected = VirtualGamepadState()
    expected.buttons = 1 << 15
    expected.leftStickX = Int16(Float(0.01) * 32_767)
    #expect(
      backend.publishedReports().last == OJDGenericGamepadFormat().buildInputReport(from: expected)
    )
    try await dispatcher.send(RemappingGamepadState(buttons: [.back]), for: identifier)
    expected = VirtualGamepadState()
    expected.buttons = 1 << 9
    #expect(
      backend.publishedReports().last == OJDGenericGamepadFormat().buildInputReport(from: expected)
    )
    await dispatcher.setOutputSuppressed(true)
    try await dispatcher.send(.neutral, for: identifier)
    #expect(
      backend.publishedReports().last
        == OJDGenericGamepadFormat().buildInputReport(from: VirtualGamepadState())
    )
    await dispatcher.close()
  }

  @Test func remappingReceivesNativeDeliveryFailure() async {
    let backend = UserSpaceDispatcherTestBackend(failsSend: true)
    let dispatcher = UserSpaceOutputDispatcher { _ in backend }
    await #expect(throws: UserSpaceDispatcherTestBackend.SendFailure.self) {
      try await dispatcher.send(
        RemappingGamepadState(buttons: [.south]),
        for: DeviceIdentifier(vendorID: 1, productID: 2)
      )
    }
    #expect(backend.counts().close == 1)
    await dispatcher.close()
  }

  @Test func activationCreatesAndNeutralizesEveryController() async throws {
    let created = LockedBackends()
    let dispatcher = UserSpaceOutputDispatcher { _ in
      let backend = UserSpaceDispatcherTestBackend()
      created.append(backend)
      return backend
    }
    let identifiers = [
      DeviceIdentifier(vendorID: 1, productID: 2), DeviceIdentifier(vendorID: 3, productID: 4),
      DeviceIdentifier(vendorID: 5, productID: 6)
    ]

    try await dispatcher.activate(for: identifiers)

    #expect(created.snapshot().count == identifiers.count)
    #expect(created.snapshot().allSatisfy { $0.counts().send >= 1 })
    #expect(dispatcher.status == "on (devices=3)")
    await dispatcher.close()
  }

  @Test func idleKeepalivePublishesRepeatInterruptReportsAndStateChanges() async throws {
    let backend = UserSpaceDispatcherTestBackend()
    let dispatcher = UserSpaceOutputDispatcher { _ in backend }
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2)

    try await dispatcher.activate(for: [identifier])
    #expect(backend.counts().send >= 1)

    let deadline = ContinuousClock.now.advanced(by: .milliseconds(250))
    while backend.counts().send < 2, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(8))
    }
    let idleSends = backend.counts().send
    #expect(idleSends >= 2)

    let idle = try #require(backend.publishedReports().last)
    await dispatcher.dispatch(events: [.buttonPressed(.a)], from: identifier)
    #expect(backend.counts().send > idleSends)
    let pressed = try #require(backend.publishedReports().last)
    #expect(pressed != idle)

    await dispatcher.close()
    #expect(backend.counts().close == 1)
  }

  @Test func activationSendFailureClosesPartialDevicesForEveryFailurePosition() async {
    let identifiers = [
      DeviceIdentifier(vendorID: 1, productID: 2), DeviceIdentifier(vendorID: 3, productID: 4),
      DeviceIdentifier(vendorID: 5, productID: 6)
    ]
    for failureIndex in identifiers.indices {
      let created = LockedBackends()
      let attempt = LockedCounter()
      let dispatcher = UserSpaceOutputDispatcher { _ in
        let index = attempt.next()
        let backend = UserSpaceDispatcherTestBackend(failsSend: index == failureIndex)
        created.append(backend)
        return backend
      }

      do {
        try await dispatcher.activate(for: identifiers)
        Issue.record("Activation unexpectedly succeeded")
      } catch {}

      #expect(dispatcher.status == "off")
      #expect(created.snapshot().count == failureIndex + 1)
      #expect(created.snapshot().allSatisfy { $0.counts().close == 1 })
    }
  }

  @Test func activationCreationFailureClosesPartialDevicesForEveryFailurePosition() async {
    let identifiers = [
      DeviceIdentifier(vendorID: 1, productID: 2), DeviceIdentifier(vendorID: 3, productID: 4),
      DeviceIdentifier(vendorID: 5, productID: 6)
    ]
    for failureIndex in identifiers.indices {
      let created = LockedBackends()
      let attempt = LockedCounter()
      let dispatcher = UserSpaceOutputDispatcher { _ in
        let index = attempt.next()
        if index == failureIndex { throw UserSpaceDispatcherTestBackend.SendFailure() }
        let backend = UserSpaceDispatcherTestBackend()
        created.append(backend)
        return backend
      }

      do {
        try await dispatcher.activate(for: identifiers)
        Issue.record("Activation unexpectedly succeeded")
      } catch {}

      #expect(dispatcher.status == "off")
      #expect(created.snapshot().allSatisfy { $0.counts().close == 1 })
    }
  }

  @Test func activationSurfacesNeutralReportSendFailure() async {
    let backend = UserSpaceDispatcherTestBackend(failsSend: true)
    let dispatcher = UserSpaceOutputDispatcher { _ in backend }

    do {
      try await dispatcher.activate(for: [DeviceIdentifier(vendorID: 1, productID: 2)])
      Issue.record("Activation unexpectedly succeeded")
    } catch is UserSpaceDispatcherTestBackend.SendFailure {
      #expect(backend.counts().close == 1)
      #expect(dispatcher.status == "off")
    } catch { Issue.record("Unexpected activation error") }
  }

  @Test func closeDrainsCapturedDispatchBeforeReleasingBackend() async throws {
    let sendGate = UserSpaceDispatcherTestGate()
    let backend = UserSpaceDispatcherTestBackend(sendGate: sendGate)
    let dispatcher = UserSpaceOutputDispatcher { _ in backend }

    let dispatchTask = Task {
      await dispatcher.dispatch(
        events: [.buttonPressed(.a)],
        from: DeviceIdentifier(vendorID: 1, productID: 2)
      )
    }
    await sendGate.waitUntilWaiting()

    let close = dispatcher.beginClose()
    #expect(backend.counts().close == 0)
    await sendGate.open()
    await dispatchTask.value
    await close.value

    let counts = backend.counts()
    #expect(counts.send == 1)
    #expect(counts.close == 1)
    #expect(dispatcher.status == "off")
  }

  @Test func creationCompletionAfterCloseClosesUninstalledBackend() async {
    let creationGate = UserSpaceDispatcherTestGate()
    let backend = UserSpaceDispatcherTestBackend()
    let dispatcher = UserSpaceOutputDispatcher { _ in
      await creationGate.wait()
      return backend
    }
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2)

    let dispatchTask = Task { await dispatcher.dispatch(events: [], from: identifier) }
    await creationGate.waitUntilWaiting()

    let close = dispatcher.beginClose()
    await creationGate.open()
    await dispatchTask.value
    await close.value

    let counts = backend.counts()
    #expect(counts.send == 0)
    #expect(counts.close == 1)
    #expect(dispatcher.status == "off")
    await dispatcher.close()
    #expect(backend.counts().close == 1)
  }

  @Test func controllerStopRetiresBackendBeforeLifecycleCallback() async throws {
    let backend = UserSpaceDispatcherTestBackend()
    let observedCloseCount = LockedCounter()
    let dispatcher = UserSpaceOutputDispatcher(
      testBackendFactory: { _ in backend },
      onControllerDidStop: { _ in if backend.counts().close == 1 { _ = observedCloseCount.next() } }
    )
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2)

    try await dispatcher.activate(for: [identifier])
    await dispatcher.controllerDidStop(identifier)

    #expect(backend.counts().close == 1)
    #expect(observedCloseCount.current() == 1)
  }

  @Test func controllerStopWaitsForCancellationNoncooperativeCreationBeforeCallback() async {
    let creationGate = UserSpaceDispatcherTestGate()
    let backend = UserSpaceDispatcherTestBackend()
    let callbackCount = LockedCounter()
    let callbackCloseCount = LockedCounter()
    let dispatcher = UserSpaceOutputDispatcher(
      testBackendFactory: { _ in
        await creationGate.wait()
        return backend
      },
      onControllerDidStop: { _ in
        _ = callbackCount.next()
        if backend.counts().close == 1 { _ = callbackCloseCount.next() }
      }
    )
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2)

    let dispatchTask = Task { await dispatcher.dispatch(events: [], from: identifier) }
    await creationGate.waitUntilWaiting()

    let stopTask = Task { await dispatcher.controllerDidStop(identifier) }
    for _ in 0..<10 { await Task.yield() }
    #expect(callbackCount.current() == 0)

    await creationGate.open()
    await stopTask.value
    await dispatchTask.value

    #expect(backend.counts().close == 1)
    #expect(callbackCloseCount.current() == 1)
  }
}

private final class LockedBackends: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [UserSpaceDispatcherTestBackend] = []

  func append(_ backend: UserSpaceDispatcherTestBackend) {
    lock.withLock { values.append(backend) }
  }
  func snapshot() -> [UserSpaceDispatcherTestBackend] { lock.withLock { values } }
}

private final class LockedCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  func next() -> Int {
    lock.withLock {
      defer { value += 1 }
      return value
    }
  }

  func current() -> Int { lock.withLock { value } }
}
