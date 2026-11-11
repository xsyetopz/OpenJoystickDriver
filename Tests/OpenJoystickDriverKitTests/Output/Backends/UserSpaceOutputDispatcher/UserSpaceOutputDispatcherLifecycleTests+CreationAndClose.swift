import Foundation
import Testing

@testable import OpenJoystickDriverKit

extension UserSpaceOutputDispatcherLifecycleTests {
  @Test
  func activationCreationFailureClosesPartialDevicesForEveryFailurePosition() async {
    let identifiers = [
      LogicalControllerID(vendorID: 1, productID: 2),
      LogicalControllerID(vendorID: 3, productID: 4),
      LogicalControllerID(vendorID: 5, productID: 6),
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

      #expect(created.snapshot().allSatisfy { $0.counts().close == 1 })
    }
  }

  @Test
  func activationSurfacesNeutralReportSendFailure() async {
    let backend = UserSpaceDispatcherTestBackend(failsSend: true)
    let dispatcher = UserSpaceOutputDispatcher { _ in backend }

    do {
      try await dispatcher.activate(for: [LogicalControllerID(vendorID: 1, productID: 2)])
      Issue.record("Activation unexpectedly succeeded")
    } catch is UserSpaceDispatcherTestBackend.SendFailure {
      #expect(backend.counts().close == 1)
    } catch { Issue.record("Unexpected activation error") }
  }

  @Test
  func closeCancelsBackendBeforeDrainingCapturedDispatch() async {
    let sendGate = UserSpaceDispatcherTestGate()
    let backend = UserSpaceDispatcherTestBackend(sendGate: sendGate)
    let dispatcher = UserSpaceOutputDispatcher { _ in backend }

    let dispatchTask = Task {
      await dispatcher.dispatch(
        changes: [.press(.south)],
        from: LogicalControllerID(vendorID: 1, productID: 2)
      )
    }
    await sendGate.waitUntilWaiting()

    let close = dispatcher.beginClose()
    #expect(backend.counts().close == 1)
    await sendGate.open()
    await dispatchTask.value
    await close.value

    let counts = backend.counts()
    #expect(counts.send == 0)
    #expect(counts.close == 1)
  }

  @Test
  func creationCompletionAfterCloseClosesUninstalledBackend() async {
    let creationGate = UserSpaceDispatcherTestGate()
    let backend = UserSpaceDispatcherTestBackend()
    let dispatcher = UserSpaceOutputDispatcher { _ in
      await creationGate.wait()
      return backend
    }
    let identifier = LogicalControllerID(vendorID: 1, productID: 2)

    let dispatchTask = Task { await dispatcher.activateOutput(for: identifier) }
    await creationGate.waitUntilWaiting()

    let close = dispatcher.beginClose()
    await creationGate.open()
    await dispatchTask.value
    await close.value

    let counts = backend.counts()
    #expect(counts.send == 0)
    #expect(counts.close == 1)
    #expect(backend.activations().activated == 0)
    await dispatcher.close()
    #expect(backend.counts().close == 1)
  }

  @Test
  func aCreatedDeviceIsActivatedOnceBeforeItsFirstReport() async throws {
    let backend = UserSpaceDispatcherTestBackend()
    let dispatcher = UserSpaceOutputDispatcher { _ in backend }
    let identifier = LogicalControllerID(vendorID: 1, productID: 2)

    try await dispatcher.activate(for: [identifier])
    await dispatcher.dispatch(changes: [.press(.south)], from: identifier)
    await dispatcher.close()

    let activations = backend.activations()
    #expect(activations.activated == 1)
    #expect(activations.sendsBefore == 0)
    #expect(backend.counts().send > 0)
  }

  @Test
  func controllerStopRetiresBackendBeforeLifecycleCallback() async throws {
    let backend = UserSpaceDispatcherTestBackend()
    let observedCloseCount = LockedCounter()
    let dispatcher = UserSpaceOutputDispatcher(
      testBackendFactory: { _ in backend },
      onControllerDidStop: { _ in if backend.counts().close == 1 { _ = observedCloseCount.next() } }
    )
    let identifier = LogicalControllerID(vendorID: 1, productID: 2)

    try await dispatcher.activate(for: [identifier])
    await dispatcher.controllerDidStop(identifier)

    #expect(backend.counts().close == 1)
    #expect(observedCloseCount.current() == 1)
  }

  @Test
  func controllerStopWaitsForCancellationNoncooperativeCreationBeforeCallback() async {
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
    let identifier = LogicalControllerID(vendorID: 1, productID: 2)

    let dispatchTask = Task { await dispatcher.activateOutput(for: identifier) }
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

  func set(_ output: ExpectedButtonOutput, pressed: Bool, in state: inout VirtualGamepadState) {
    switch output {
    case .bit(let bit):
      if pressed { state.buttons |= 1 << bit } else { state.buttons &= ~(1 << bit) }
    case .leftTrigger: state.leftTriggerPressed = pressed
    case .rightTrigger: state.rightTriggerPressed = pressed
    }
  }

  func verifyContinuity(
    pressed: InputChange,
    heldWith: InputChange,
    released: InputChange,
    later: InputChange,
    expectedState: (Int) -> VirtualGamepadState
  ) async {
    let backend = UserSpaceDispatcherTestBackend()
    let format = ContinuitySnapshotReportFormat()
    let dispatcher = UserSpaceOutputDispatcher(testBackendFactory: { _ in backend }, format: format)
    let identifier = LogicalControllerID(vendorID: 1, productID: 2)

    for (stage, event) in [pressed, heldWith, released, later].enumerated() {
      await dispatcher.dispatch(changes: [event], from: identifier)
      #expect(
        backend.publishedReports().last == format.buildInputReport(from: expectedState(stage))
      )
    }
    await dispatcher.close()
  }
}
