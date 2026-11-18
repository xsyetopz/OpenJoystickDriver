import Testing

@testable import OpenJoystickDriverKit

/// Stick Y is positive down.
///
/// Each test starts from the physical stick pushed up (`y: -1`) and follows it to the direction of
/// the event that leaves the engine.
struct StickYDirectionTests {
  private let device = LogicalControllerID(vendorID: 1, productID: 2, locationID: 1)

  @Test(arguments: [true, false])
  func stickUpFiresNegativeYDirectionBinding(left: Bool) throws {
    let axis: RemappingAxis = left ? .leftStickY : .rightStickY
    let profile = RemappingProfile(
      name: "Y directions",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [
        RemappingBinding(
          source: .axisDirection(axis, .negative),
          destination: .keyboard(key: .a, modifiers: []),
          axisTuning: RemappingAxisTuning(deadzone: 0)
        ),
        RemappingBinding(
          source: .axisDirection(axis, .positive),
          destination: .keyboard(key: .b, modifiers: []),
          axisTuning: RemappingAxisTuning(deadzone: 0)
        ),
      ]
    )
    try profile.validate()
    func stick(_ y: Float) -> InputChange {
      left ? .leftStick(x: 0, y: y) : .rightStick(x: 0, y: y)
    }
    var state = RemappingEngineState()
    #expect(
      state.process(inputs: [stick(-1)], from: device, profile: profile, at: 0)
        == [.system(.keyDown(.a))]
    )
    #expect(
      state.process(inputs: [stick(0)], from: device, profile: profile, at: 1)
        == [.system(.keyUp(.a))]
    )
    #expect(
      state.process(inputs: [stick(1)], from: device, profile: profile, at: 2)
        == [.system(.keyDown(.b))]
    )
  }

  @Test
  func stickUpMovesPointerUpInEveryPointerMode() {
    for mode in [RemappingStickMode.pointerArea, .pointerRing] {
      var stick = RemappingStickRuntime(
        mapping: RemappingStickMapping(
          source: .left,
          mode: mode,
          tuning: RemappingStickTuning(innerDeadzone: 0),
          pointerRadiusPoints: 100
        )
      )
      #expect(stick.update(x: 0, y: -0.5, at: 0).pointerDelta.y < 0)
      #expect(stick.update(x: 0, y: 0.5, at: 1).pointerDelta.y > 0)
    }
    var aim = RemappingStickRuntime(
      mapping: RemappingStickMapping(
        source: .left,
        tuning: RemappingStickTuning(innerDeadzone: 0),
        aimDegreesPerSecond: 100,
        pointerPointsPerDegree: 2
      )
    )
    _ = aim.update(x: 0, y: -1, at: 0)
    #expect(aim.advance(at: 10_000_000).pointerDelta == SIMD2(0, -2))
  }

  @Test
  func stickUpMovesPointerUpThroughEngine() {
    var engine = RemappingEngineState()
    let profile = RemappingProfile(
      name: "Aim",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .passthrough),
      stickMappings: [
        RemappingStickMapping(
          source: .left,
          tuning: RemappingStickTuning(innerDeadzone: 0),
          aimDegreesPerSecond: 100
        )
      ],
      bindings: []
    )
    _ = engine.process(inputs: [.leftStick(x: 0, y: -1)], from: device, profile: profile, at: 0)
    #expect(engine.tick(at: 10_000_000) == [.system(.pointerDelta(x: 0, y: -1))])
  }

  @Test
  func flickForwardIsStickUpAndTurnsClockwiseTowardRight() {
    var stick = RemappingFlickStick()
    #expect(stick.process(x: 0, y: -1) == .flick(degrees: 0))
    var right = RemappingFlickStick()
    #expect(right.process(x: 1, y: 0) == .flick(degrees: 90))
    var down = RemappingFlickStick()
    #expect(down.process(x: 0, y: 1) == .flick(degrees: 180))
  }

  @Test
  func clockwiseRotationScrollsAndSteersPositive() {
    var scroll = RemappingStickRuntime(
      mapping: RemappingStickMapping(
        source: .left,
        mode: .scrollWheel,
        tuning: RemappingStickTuning(innerDeadzone: 0),
        scrollDegreesPerLine: 30,
        rotationDirection: .clockwise
      )
    )
    _ = scroll.update(x: 0, y: -1, at: 0)
    #expect(scroll.update(x: 1, y: 0, at: 1).scrollLines == SIMD2(0, 3))
    var steering = RemappingStickRuntime(
      mapping: RemappingStickMapping(
        source: .left,
        mode: .steering,
        tuning: RemappingStickTuning(innerDeadzone: 0),
        rotationDirection: .clockwise,
        steeringDegreesAtFullScale: 180
      )
    )
    _ = steering.update(x: 0, y: -1, at: 0)
    #expect(steering.update(x: 1, y: 0, at: 1).virtualAxes[.leftStickX] == 0.5)
  }
}
