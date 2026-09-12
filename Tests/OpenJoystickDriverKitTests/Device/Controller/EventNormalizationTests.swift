import Testing

@testable import OpenJoystickDriverKit

struct ControllerEventNormalizerTests {
  @Test func duplicateButtonEventsCollapseToOneEffectiveTransition() {
    let state = DeviceInputState(vendorID: 1, productID: 2)
    let result = ControllerEventNormalizer.normalize(
      [.buttonPressed(.a), .buttonPressed(.a)],
      from: state
    )

    #expect(result.events == [.buttonPressed(.a)])
    #expect(result.suppressedEventCount == 1)
  }

  @Test func contradictoryPulseWithinOnePacketDoesNotMisfire() {
    let state = DeviceInputState(vendorID: 1, productID: 2)
    let result = ControllerEventNormalizer.normalize(
      [.buttonPressed(.a), .buttonReleased(.a)],
      from: state
    )

    #expect(result.events.isEmpty)
    #expect(result.suppressedEventCount == 2)
  }

  @Test func releaseThenPressOfAlreadyHeldButtonIsNoOp() {
    var state = DeviceInputState(vendorID: 1, productID: 2)
    state.apply(events: [.buttonPressed(.a)])
    let result = ControllerEventNormalizer.normalize(
      [.buttonReleased(.a), .buttonPressed(.a)],
      from: state
    )

    #expect(result.events.isEmpty)
  }

  @Test func analogEventsUseFinalValueAndSanitizeInvalidComponents() {
    let state = DeviceInputState(vendorID: 1, productID: 2)
    let result = ControllerEventNormalizer.normalize(
      [
        .leftStickChanged(x: 0.2, y: 0.3), .leftStickChanged(x: 2, y: .nan),
        .leftStickChanged(x: 0.8, y: -2), .leftTriggerChanged(.infinity), .rightTriggerChanged(1.5)
      ],
      from: state
    )

    #expect(result.events == [.leftStickChanged(x: 0.8, y: -1), .rightTriggerChanged(1)])
    #expect(result.adjustedAnalogValueCount == 5)
    #expect(result.suppressedEventCount == 3)
  }

  @Test func directDpadButtonsBecomeOneCanonicalDirection() {
    let state = DeviceInputState(vendorID: 1, productID: 2)
    let result = ControllerEventNormalizer.normalize(
      [.buttonPressed(.dpadUp), .buttonPressed(.dpadRight)],
      from: state
    )

    #expect(result.events == [.dpadChanged(.northEast)])
    #expect(result.suppressedEventCount == 1)
  }

  @Test func outputOrderingIsStableAcrossParserEventOrder() {
    let state = DeviceInputState(vendorID: 1, productID: 2)
    let first = ControllerEventNormalizer.normalize(
      [
        .rightTriggerChanged(0.5), .buttonPressed(.b), .leftStickChanged(x: 0.4, y: -0.2),
        .buttonPressed(.a)
      ],
      from: state
    )
    let second = ControllerEventNormalizer.normalize(
      [
        .buttonPressed(.a), .leftStickChanged(x: 0.4, y: -0.2), .buttonPressed(.b),
        .rightTriggerChanged(0.5)
      ],
      from: state
    )

    #expect(first.events == second.events)
    #expect(
      first.events == [
        .buttonPressed(.a), .buttonPressed(.b), .leftStickChanged(x: 0.4, y: -0.2),
        .rightTriggerChanged(0.5)
      ]
    )
  }

  @Test func repeatedSensorSamplesKeepTheirOrderWithoutChangingControlState() {
    let state = DeviceInputState(vendorID: 1, productID: 2)
    let timestamp = ControllerSampleTimestamp(
      rawCounter: 12,
      elapsedNanoseconds: 0,
      tickNanosecondsNumerator: 1000,
      tickNanosecondsDenominator: 3,
      sequenceIndex: 0
    )
    let motion = ControllerEvent.motionSample(
      ControllerMotionSample(
        timestamp: timestamp,
        rawGyroscope: ControllerRawSensorVector(x: 1, y: 2, z: 3),
        rawAccelerometer: ControllerRawSensorVector(x: 4, y: 5, z: 6)
      )
    )
    let touch = ControllerEvent.touchSample(
      ControllerTouchSample(
        reportTimestamp: timestamp,
        rawTouchCounter: nil,
        historyIndex: 0,
        width: 1920,
        height: 1080,
        contacts: [ControllerTouchContact(id: 1, isActive: true, x: 200, y: 100)]
      )
    )
    let result = ControllerEventNormalizer.normalize(
      [motion, .buttonPressed(.a), touch, motion, .buttonPressed(.a)],
      from: state
    )
    #expect(result.events == [.buttonPressed(.a), motion, touch, motion])
    #expect(result.suppressedEventCount == 1)
    #expect(result.adjustedAnalogValueCount == 0)
    let samples = ControllerEventNormalizer.normalize([motion, touch, motion], from: state)
    #expect(samples.events == [motion, touch, motion])
    let applied = state.applying(events: samples.events)
    #expect(applied.pressedButtons == state.pressedButtons)
    #expect(applied.leftStickX == state.leftStickX)
    #expect(applied.leftStickY == state.leftStickY)
    #expect(applied.rightStickX == state.rightStickX)
    #expect(applied.rightStickY == state.rightStickY)
    #expect(applied.leftTrigger == state.leftTrigger)
    #expect(applied.rightTrigger == state.rightTrigger)
    #expect(applied.touchSamples.count == 1)
  }

}
