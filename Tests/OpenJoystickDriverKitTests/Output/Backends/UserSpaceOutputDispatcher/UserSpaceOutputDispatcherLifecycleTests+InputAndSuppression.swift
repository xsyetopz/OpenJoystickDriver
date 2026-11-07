import Foundation
import Testing

@testable import OpenJoystickDriverKit

extension UserSpaceOutputDispatcherLifecycleTests {
  @Test
  func everyAcceptedButtonPreservesHoldReleaseAndLaterInput() async {
    let supported: [(Control, ExpectedButtonOutput)] = [
      (.south, .bit(0)), (.east, .bit(1)), (.west, .bit(2)), (.north, .bit(3)),
      (.leftShoulder, .bit(4)), (.rightShoulder, .bit(5)), (.leftStickClick, .bit(6)),
      (.rightStickClick, .bit(7)), (.start, .bit(8)), (.back, .bit(9)), (.guide, .bit(10)),
      (.capture, .bit(15)), (.leftTrigger, .leftTrigger), (.rightTrigger, .rightTrigger),
    ]
    let unsupported: [Control] = [
      .leftPaddle1, .leftPaddle2, .rightPaddle1, .rightPaddle2, .auxiliary1, .auxiliary2,
      .auxiliary3, .auxiliary4, .auxiliary5, .auxiliary6, .auxiliary7, .auxiliary8, .leftStickTouch,
      .rightStickTouch, .leftTrackpadClick, .rightTrackpadClick, .leftTrackpadTouch,
      .rightTrackpadTouch, .touchpadClick, .microphone, .pointerX, .pointerY, .pointerTracking,
    ]
    let analog: [Control] = [.leftStickX, .leftStickY, .rightStickX, .rightStickY]
    #expect(
      Set(supported.map(\.0) + unsupported + analog).union(Control.dpad) == Set(Control.allCases)
    )

    for (control, output) in supported {
      let backend = UserSpaceDispatcherTestBackend()
      let format = ContinuitySnapshotReportFormat()
      let dispatcher = UserSpaceOutputDispatcher(
        testBackendFactory: { _ in backend },
        format: format
      )
      let identifier = LogicalControllerID(vendorID: 1, productID: 2)
      var expected = VirtualGamepadState()

      await dispatcher.dispatch(changes: [.press(control)], from: identifier)
      set(output, pressed: true, in: &expected)
      #expect(backend.publishedReports().last == format.buildInputReport(from: expected))

      await dispatcher.dispatch(
        changes: [.leftStick(x: 0.5, y: -0.25)],
        from: identifier
      )
      expected.leftStickX = Int16(0.5 * 32_767)
      expected.leftStickY = Int16(-0.25 * 32_767)
      #expect(backend.publishedReports().last == format.buildInputReport(from: expected))

      await dispatcher.dispatch(changes: [.release(control)], from: identifier)
      set(output, pressed: false, in: &expected)
      #expect(backend.publishedReports().last == format.buildInputReport(from: expected))

      await dispatcher.dispatch(changes: [.rightTrigger(0.75)], from: identifier)
      expected.rightTrigger = Int16(0.75 * 32_767)
      #expect(backend.publishedReports().last == format.buildInputReport(from: expected))
      await dispatcher.close()
    }

    let backend = UserSpaceDispatcherTestBackend()
    let format = ContinuitySnapshotReportFormat()
    let dispatcher = UserSpaceOutputDispatcher(testBackendFactory: { _ in backend }, format: format)
    let identifier = LogicalControllerID(vendorID: 3, productID: 4)
    let neutral = format.buildInputReport(from: VirtualGamepadState())
    for control in unsupported {
      await dispatcher.dispatch(changes: [.press(control)], from: identifier)
      #expect(backend.publishedReports().last == neutral, "\(control) must remain unsupported")
      await dispatcher.dispatch(changes: [.release(control)], from: identifier)
    }
    await dispatcher.close()
  }

  @Test
  func dpadSticksAndTriggersPreserveTransitionsAcrossUnrelatedInput() async {
    let dpadCases: [(HatDirection, GamepadHIDDescriptor.Hat)] = [
      (.north, .north), (.northEast, .northEast), (.east, .east), (.southEast, .southEast),
      (.south, .south), (.southWest, .southWest), (.west, .west), (.northWest, .northWest),
    ]
    for (direction, hat) in dpadCases {
      var expected = VirtualGamepadState()
      await verifyContinuity(
        pressed: .hat(direction),
        heldWith: .leftStick(x: 0.5, y: -0.25),
        released: .hat(.neutral),
        later: .rightTrigger(0.75)
      ) { stage in
        switch stage {
        case 0:
          expected.hat = hat
          expected.buttons = GamepadHIDDescriptor.dpadButtonBits(for: hat)
        case 1:
          expected.leftStickX = Int16(0.5 * 32_767)
          expected.leftStickY = Int16(-0.25 * 32_767)
        case 2:
          expected.hat = .neutral
          expected.buttons = 0
        default: expected.rightTrigger = Int16(0.75 * 32_767)
        }
        return expected
      }
    }

    let analogCases: [(InputChange, InputChange, (inout VirtualGamepadState, Bool) -> Void)] = [
      (
        .leftStick(x: 0.75, y: -0.5), .leftStick(x: 0, y: 0),
        { state, pressed in
          state.leftStickX = pressed ? Int16(0.75 * 32_767) : 0
          state.leftStickY = pressed ? Int16(-0.5 * 32_767) : 0
        }
      ),
      (
        .rightStick(x: -0.5, y: 0.75), .rightStick(x: 0, y: 0),
        { state, pressed in
          state.rightStickX = pressed ? Int16(-0.5 * 32_767) : 0
          state.rightStickY = pressed ? Int16(0.75 * 32_767) : 0
        }
      ),
      (
        .leftTrigger(0.75), .leftTrigger(0),
        { state, pressed in state.leftTrigger = pressed ? Int16(0.75 * 32_767) : 0 }
      ),
      (
        .rightTrigger(0.75), .rightTrigger(0),
        { state, pressed in state.rightTrigger = pressed ? Int16(0.75 * 32_767) : 0 }
      ),
    ]
    for (pressed, released, update) in analogCases {
      var expected = VirtualGamepadState()
      await verifyContinuity(
        pressed: pressed,
        heldWith: .press(.west),
        released: released,
        later: .press(.south)
      ) { stage in
        switch stage {
        case 0: update(&expected, true)
        case 1: expected.buttons |= 1 << 2
        case 2: update(&expected, false)
        default: expected.buttons |= 1
        }
        return expected
      }
    }
  }

  @Test
  func virtualOutputSuppressionPublishesDeviceWithoutForwardingInput() async {
    let backend = UserSpaceDispatcherTestBackend()
    let creations = LockedCounter()
    let dispatcher = UserSpaceOutputDispatcher { _ in
      _ = creations.next()
      return backend
    }
    let identifier = LogicalControllerID(vendorID: 1, productID: 2)
    await dispatcher.setOutputSuppressed(true)

    await dispatcher.dispatch(changes: [.press(.south)], from: identifier)

    #expect(creations.current() == 1)
    #expect(backend.publishedReports().isEmpty)
    #expect(backend.counts().close == 0)
    await dispatcher.close()
  }

  @Test
  func virtualOutputSuppressionNeutralizesWithoutRetiringDevice() async throws {
    let backend = UserSpaceDispatcherTestBackend()
    let dispatcher = UserSpaceOutputDispatcher { _ in backend }
    let identifier = LogicalControllerID(vendorID: 1, productID: 2)
    await dispatcher.dispatch(changes: [.press(.south)], from: identifier)

    await dispatcher.setOutputSuppressed(true)

    #expect(
      backend.publishedReports().last
        == OJDGenericGamepadFormat().buildInputReport(from: VirtualGamepadState())
    )
    #expect(backend.counts().close == 0)
    // Released while suppressed: a snapshot carries every held control, so South must be let go.
    await dispatcher.dispatch(changes: [.release(.south)], from: identifier)

    await dispatcher.setOutputSuppressed(false)
    await dispatcher.dispatch(changes: [.press(.east)], from: identifier)
    var expected = VirtualGamepadState()
    expected.buttons = 1 << GamepadHIDDescriptor.ButtonBit.b.rawValue
    #expect(
      backend.publishedReports().last == OJDGenericGamepadFormat().buildInputReport(from: expected)
    )
    #expect(backend.counts().close == 0)
    await dispatcher.close()
  }

  @Test
  func neutralRetryAfterRetirementDoesNotCreateAnotherDevice() async throws {
    let creations = LockedCounter()
    let dispatcher = UserSpaceOutputDispatcher { _ in
      _ = creations.next()
      return UserSpaceDispatcherTestBackend()
    }
    let identifier = LogicalControllerID(vendorID: 1, productID: 2)
    try await dispatcher.send(.neutral, for: identifier)
    #expect(creations.current() == 0)
    try await dispatcher.send(RemappingGamepadState(buttons: [.south]), for: identifier)
    await dispatcher.controllerDidStop(identifier)
    try await dispatcher.send(.neutral, for: identifier)
    #expect(creations.current() == 1)
    await dispatcher.close()
  }

  @Test
  func stateHeldBeforeSuppressionIsRepublishedAfterItLifts() async throws {
    let backend = UserSpaceDispatcherTestBackend()
    let dispatcher = UserSpaceOutputDispatcher { _ in backend }
    let identifier = LogicalControllerID(vendorID: 1, productID: 2)
    await dispatcher.dispatch(changes: [.press(.south)], from: identifier)
    let pressed = try #require(backend.publishedReports().last)

    await dispatcher.setOutputSuppressed(true)
    #expect(backend.publishedReports().last != pressed)
    await dispatcher.setOutputSuppressed(false)
    await dispatcher.dispatch(changes: [.press(.south)], from: identifier)

    #expect(backend.publishedReports().last == pressed)
    await dispatcher.close()
  }

  @Test
  func remappedReportsUseTheirOwnSuppressionGate() async throws {
    let backend = UserSpaceDispatcherTestBackend()
    let dispatcher = UserSpaceOutputDispatcher { _ in backend }
    let identifier = LogicalControllerID(vendorID: 1, productID: 2)
    await dispatcher.setOutputSuppressed(true)
    await dispatcher.dispatch(changes: [.press(.south)], from: identifier)
    #expect(backend.publishedReports().isEmpty)
    try await dispatcher.send(RemappingGamepadState(buttons: [.north]), for: identifier)
    #expect(!backend.publishedReports().isEmpty)
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

  @Test
  func remappedStatePreservesSmallAxesAndDistinctShareThenReplacesHeldState() async throws {
    let backend = UserSpaceDispatcherTestBackend()
    let dispatcher = UserSpaceOutputDispatcher { _ in backend }
    let identifier = LogicalControllerID(vendorID: 1, productID: 2)
    try await dispatcher.send(
      RemappingGamepadState(buttons: [.capture], axes: [.leftStickX: 0.01]),
      for: identifier
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

  @Test
  func remappingReceivesNativeDeliveryFailure() async {
    let backend = UserSpaceDispatcherTestBackend(failsSend: true)
    let dispatcher = UserSpaceOutputDispatcher { _ in backend }
    await #expect(throws: UserSpaceDispatcherTestBackend.SendFailure.self) {
      try await dispatcher.send(
        RemappingGamepadState(buttons: [.south]),
        for: LogicalControllerID(vendorID: 1, productID: 2)
      )
    }
    #expect(backend.counts().close == 1)
    await dispatcher.close()
  }

  @Test
  func activationCreatesAndNeutralizesEveryController() async throws {
    let created = LockedBackends()
    let dispatcher = UserSpaceOutputDispatcher { _ in
      let backend = UserSpaceDispatcherTestBackend()
      created.append(backend)
      return backend
    }
    let identifiers = [
      LogicalControllerID(vendorID: 1, productID: 2),
      LogicalControllerID(vendorID: 3, productID: 4),
      LogicalControllerID(vendorID: 5, productID: 6),
    ]

    try await dispatcher.activate(for: identifiers)

    #expect(created.snapshot().count == identifiers.count)
    #expect(created.snapshot().allSatisfy { $0.counts().send >= 1 })
    await dispatcher.close()
  }

  @Test
  func idleDevicePublishesOnlyOnInput() async throws {
    let backend = UserSpaceDispatcherTestBackend()
    let dispatcher = UserSpaceOutputDispatcher { _ in backend }
    let identifier = LogicalControllerID(vendorID: 1, productID: 2)

    try await dispatcher.activate(for: [identifier])
    let idleSends = backend.counts().send
    #expect(idleSends == 1)
    try await Task.sleep(for: .milliseconds(50))
    #expect(backend.counts().send == idleSends)

    let idle = try #require(backend.publishedReports().last)
    await dispatcher.dispatch(changes: [.press(.south)], from: identifier)
    #expect(backend.counts().send > idleSends)
    let pressed = try #require(backend.publishedReports().last)
    #expect(pressed != idle)

    let pressedSends = backend.counts().send
    // The same snapshot again publishes nothing.
    await dispatcher.dispatch(changes: [], from: identifier)
    #expect(backend.counts().send == pressedSends)

    await dispatcher.close()
    #expect(backend.counts().close == 1)
  }

  @Test


  func activationSendFailureClosesPartialDevicesForEveryFailurePosition() async {
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

        let backend = UserSpaceDispatcherTestBackend(failsSend: index == failureIndex)
        created.append(backend)
        return backend
      }

      do {
        try await dispatcher.activate(for: identifiers)
        Issue.record("Activation unexpectedly succeeded")
      } catch {}

      #expect(created.snapshot().count == failureIndex + 1)
      #expect(created.snapshot().allSatisfy { $0.counts().close == 1 })
    }
  }

}
