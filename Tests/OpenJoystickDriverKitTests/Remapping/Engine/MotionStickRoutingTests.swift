import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct MotionStickRoutingTests {
  @Test func gravityLeanDrivesIndependentDigitalAndVirtualOutputsThenTimesOut() {
    var engine = RemappingEngineState()
    let device = DeviceIdentifier(vendorID: 1, productID: 2)
    let profile = RemappingProfile(
      name: "Motion steering",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      motionTuning: RemappingMotionTuning(
        automaticBias: false,
        lean: RemappingMotionLean(thresholdDegrees: 10, hysteresisDegrees: 2),
        steering: RemappingMotionSteering(
          deadzoneDegrees: 5, fullScaleDegrees: 45, responseExponent: 1
        )
      ),
      bindings: [RemappingBinding(
        source: .motionLean(.right),
        destination: .keyboard(key: .d, modifiers: [])
      )]
    )
    #expect(
      engine.process(
        events: [.motionSample(sample(0, time: 0))],
        from: device,
        profile: profile,
        at: 0
      ).isEmpty
    )
    let active = engine.process(
      events: [.motionSample(sample(1, time: 10_000_000))],
      from: device,
      profile: profile,
      at: 10_000_000
    )
    #expect(active.count == 2)
    guard case .gamepad(let state, _) = active[0] else {
      Issue.record("Expected motion steering output")
      return
    }
    #expect(abs(state.value(for: .leftStickX) - 0.625) < 0.000_001)
    #expect(active[1] == .system(.keyDown(.d)))
    #expect(engine.tick(at: 110_000_000) == [
      .gamepad(.neutral, device), .system(.keyUp(.d)),
    ])
    #expect(!engine.hasScheduledOutput)
  }

  @Test func profileReplacementReleasesMotionStickOwnershipImmediately() {
    var engine = RemappingEngineState()
    let device = DeviceIdentifier(vendorID: 1, productID: 2)
    let profile = RemappingProfile(
      name: "Motion lean",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      motionTuning: RemappingMotionTuning(
        automaticBias: false,
        lean: RemappingMotionLean(thresholdDegrees: 10)
      ),
      bindings: [RemappingBinding(
        source: .motionLean(.right),
        destination: .keyboard(key: .d, modifiers: [])
      )]
    )
    _ = engine.process(
      events: [.motionSample(sample(0, time: 0)), .motionSample(sample(1, time: 1))],
      from: device,
      profile: profile,
      at: 1
    )
    #expect(engine.setProfile(nil, for: device) == [.system(.keyUp(.d))])
    #expect(!engine.hasScheduledOutput)
  }

  private func sample(_ index: UInt64, time: UInt64) -> ControllerMotionSample {
    ControllerMotionSample(
      timestamp: ControllerSampleTimestamp(
        rawCounter: UInt32(index),
        elapsedNanoseconds: time,
        tickNanosecondsNumerator: nil,
        tickNanosecondsDenominator: nil,
        sequenceIndex: index,
        basis: .hostEstimate
      ),
      rawGyroscope: ControllerRawSensorVector(x: 0, y: 0, z: 0),
      rawAccelerometer: ControllerRawSensorVector(x: 0, y: 0, z: 0),
      physicalReading: ControllerMotionReading(
        gyroscopeDegreesPerSecond: ControllerMotionVector(x: 0, y: 0, z: 0),
        accelerationG: ControllerMotionVector(x: -0.5, y: sqrt(0.75), z: 0),
        calibrationSource: .nominalDeviceScale
      )
    )
  }
}
