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
        .leftStickChanged(x: 0.8, y: -2), .leftTriggerChanged(.infinity), .rightTriggerChanged(1.5),
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
        .buttonPressed(.a),
      ],
      from: state
    )
    let second = ControllerEventNormalizer.normalize(
      [
        .buttonPressed(.a), .leftStickChanged(x: 0.4, y: -0.2), .buttonPressed(.b),
        .rightTriggerChanged(0.5),
      ],
      from: state
    )

    #expect(first.events == second.events)
    #expect(
      first.events == [
        .buttonPressed(.a), .buttonPressed(.b), .leftStickChanged(x: 0.4, y: -0.2),
        .rightTriggerChanged(0.5),
      ]
    )
  }
}
