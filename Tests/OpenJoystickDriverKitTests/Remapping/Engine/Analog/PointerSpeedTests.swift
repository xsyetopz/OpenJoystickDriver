import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingPointerSpeedTests {
  private let trigger = RemappingPointerSpeedDriver(type: .trigger, side: .left)
  private let depth = RemappingPointerSpeedDriver(type: .stickDepth, side: .right)

  @Test(arguments: [
    (RemappingResponseCurve.linear, 1.25), (.easeIn, 0.875), (.easeOut, 1.625),
    (.smoothStep, 1.25),
  ])
  func scaleFollowsCurveBetweenMinAndMax(curve: RemappingResponseCurve, expected: Double) {
    let speed = RemappingPointerSpeed(driver: depth, minScale: 0.5, maxScale: 2, curve: curve)

    #expect(speed.scale(driverValue: 0.5) == expected)
    #expect(speed.scale(driverValue: 0) == 0.5)
    #expect(speed.scale(driverValue: 1) == 2)
    #expect(speed.scale(driverValue: 7) == 2)
  }

  @Test
  func fullyPulledTriggerSlowsTouchPointerToQuarter() async throws {
    let slowed = RemappingPointerSpeed(driver: trigger, minScale: 1, maxScale: 0.25)

    let released = try await touchDelta(pointerSpeed: slowed, before: [.leftTrigger(0)])
    let pulled = try await touchDelta(pointerSpeed: slowed, before: [.leftTrigger(1)])
    let plain = try await touchDelta(pointerSpeed: nil, before: [])

    #expect(plain.x != 0)
    #expect(released == plain)
    #expect(pulled.x == plain.x * 0.25)
    #expect(pulled.y == plain.y * 0.25)
  }

  @Test
  func halfDepthStickScalesTouchPointer() async throws {
    let speed = RemappingPointerSpeed(driver: depth, minScale: 0.5, maxScale: 2)

    let scaled = try await touchDelta(
      pointerSpeed: speed,
      before: [.rightStick(x: 0.3, y: 0.4)]
    )
    let plain = try await touchDelta(pointerSpeed: nil, before: [])

    #expect(abs(scaled.x / plain.x - 1.25) < 1e-3)
  }

  @Test
  func gyroMouseObeysPointerSpeed() async throws {
    let recorder = TouchOutputRecorder()
    let engine = RemappingEventEngine(sink: recorder)
    let profile = makeProfile(
      pointerSpeed: RemappingPointerSpeed(driver: trigger, minScale: 1, maxScale: 0.5),
      gyroOutput: RemappingGyroOutput(mode: .mouse, pointerPointsPerDegree: 2)
    )
    let id = device()

    try await engine.process(inputs: [.leftTrigger(1)], from: id, using: profile, at: 0)
    try await engine.process(inputs: [.motion(motion(0, time: 0))], from: id, using: profile, at: 0)
    try await engine.process(
      inputs: [.motion(motion(1, time: 10_000_000))],
      from: id,
      using: profile,
      at: 10_000_000
    )

    #expect(recorder.systemActions == [.pointerDelta(x: -1, y: -0.5)])
  }

  @Test
  func mouseMovementDestinationObeysAndScrollDoesNot() async throws {
    let tuning = RemappingAxisTuning(deadzone: 0, gain: 1)
    let bindings = [
      RemappingBinding(
        source: .axis(.rightStickX),
        destination: .mouseMovement(.x),
        axisTuning: tuning
      ),
      RemappingBinding(
        source: .axis(.rightStickY),
        destination: .scroll(.y),
        axisTuning: tuning
      ),
    ]
    let speed = RemappingPointerSpeed(driver: trigger, minScale: 1, maxScale: 0.5)
    let plain = try await actions(makeProfile(bindings: bindings), [.rightStick(x: 1, y: 1)])
    let scaled = try await actions(
      makeProfile(pointerSpeed: speed, bindings: bindings),
      [.leftTrigger(1), .rightStick(x: 1, y: 1)]
    )

    #expect(plain.count == 2)
    #expect(
      scaled
        == plain.map { action in
          guard case .mouseMoved(let axis, let amount) = action else { return action }
          return .mouseMoved(axis: axis, amount: amount * 0.5)
        }
    )
  }

  @Test(arguments: [-0.1, 10.1, Double.nan, Double.infinity])
  func validationRejectsScaleOutOfRange(scale: Double) {
    for speed in [
      RemappingPointerSpeed(driver: trigger, minScale: scale, maxScale: 1),
      RemappingPointerSpeed(driver: trigger, minScale: 1, maxScale: scale),
    ] {
      #expect(throws: RemappingValidationError.invalidPointerSpeed) {
        try makeProfile(pointerSpeed: speed).validate()
      }
    }
  }

  @Test
  func driverMustBeReportedByTheController() throws {
    let stickAndTrigger = ControllerProfileCapabilities(
      physicalInput: ControllerCapabilities(controls: [.leftTrigger, .rightStickX]),
      physicalOutput: .none
    )
    let buttonsOnly = ControllerProfileCapabilities(
      physicalInput: ControllerCapabilities(controls: [.south]),
      physicalOutput: .none
    )
    let speed = RemappingPointerSpeed(driver: trigger, minScale: 1, maxScale: 0.5)

    #expect(speed.isSupported(by: stickAndTrigger))
    #expect(!speed.isSupported(by: buttonsOnly))
    #expect(
      !RemappingPointerSpeed(driver: depth, minScale: 1, maxScale: 2).isSupported(
        by: buttonsOnly
      )
    )
  }

  @Test
  func validationAcceptsBoundsAndDocumentRoundTrips() throws {
    let profile = makeProfile(
      pointerSpeed: RemappingPointerSpeed(driver: depth, minScale: 0, maxScale: 10)
    )

    try profile.validate()
    let data = try JSONEncoder().encode(profile)
    #expect(try JSONDecoder().decode(RemappingProfile.self, from: data) == profile)
  }

  @Test
  func decodingRejectsUnknownDriverAndKeys() {
    for json in [
      #"{"driver":{"type":"Gyro","side":"Left"},"minScale":1,"maxScale":1,"curve":"Linear"}"#,
      #"{"driver":{"type":"Trigger","side":"Left"},"minScale":1,"maxScale":1}"#,
      #"{"driver":{"type":"Trigger","side":"Left"},"minScale":1,"maxScale":1,"curve":"Linear","x":1}"#,
    ] {
      #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(RemappingPointerSpeed.self, from: Data(json.utf8))
      }
    }
  }

  private func touchDelta(
    pointerSpeed: RemappingPointerSpeed?,
    before: [InputChange]
  ) async throws -> SIMD2<Double> {
    let profile = makeProfile(
      pointerSpeed: pointerSpeed,
      touchMappings: [
        RemappingTouchMapping(surface: .left, mode: .pointer, pointerSensitivity: 1_000)
      ]
    )
    let made = try await actions(
      profile,
      before + [.touch(touch(x: 0, y: 0)), .touch(touch(x: 32_768, y: 16_384))]
    )
    guard case .pointerDelta(let x, let y) = made.last else { return .zero }
    return SIMD2(x, y)
  }

  private func actions(
    _ profile: RemappingProfile,
    _ changes: [InputChange]
  ) async throws -> [RemappingSystemInputAction] {
    let recorder = TouchOutputRecorder()
    let engine = RemappingEventEngine(sink: recorder)
    for (index, change) in changes.enumerated() {
      try await engine.process(
        inputs: [change],
        from: device(),
        using: profile,
        at: UInt64(index + 1)
      )
    }
    try await engine.tick(at: UInt64(changes.count + 1))
    return recorder.systemActions
  }

  private func makeProfile(
    pointerSpeed: RemappingPointerSpeed? = nil,
    gyroOutput: RemappingGyroOutput = .default,
    touchMappings: [RemappingTouchMapping] = [],
    bindings: [RemappingBinding] = []
  ) -> RemappingProfile {
    RemappingProfile(
      name: "Speed",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      motionTuning: RemappingMotionTuning(space: .local, automaticBias: false),
      gyroOutput: gyroOutput,
      pointerSpeed: pointerSpeed,
      touchMappings: touchMappings,
      bindings: bindings
    )
  }

  private func device() -> LogicalControllerID {
    LogicalControllerID(vendorID: 1, productID: 2, locationID: 1)
  }

  private func touch(x: UInt16, y: UInt16) -> ControllerTouchSample {
    ControllerTouchSample(
      surface: .left,
      timestamp: MonotonicTimestamp(nanoseconds: 0),
      contacts: [ControllerTouchContact(slot: 0, isActive: true, x: x, y: y)]
    )
  }

  private func motion(_ index: UInt64, time: UInt64) -> ControllerMotionSample {
    ControllerMotionSample.engineSpace(
      timestamp: ControllerSampleTimestamp(
        rawCounter: 0,
        monotonic: MonotonicTimestamp(nanoseconds: time),
        tickNanosecondsNumerator: nil,
        tickNanosecondsDenominator: nil,
        sequenceIndex: index,
        basis: .hostEstimate
      ),
      gyroDegreesPerSecond: ControllerMotionVector(x: 50, y: 100, z: 0),
      accelerationG: ControllerMotionVector(x: 0, y: 1, z: 0),
      calibrationSource: .nominalDeviceScale
    )
  }
}
