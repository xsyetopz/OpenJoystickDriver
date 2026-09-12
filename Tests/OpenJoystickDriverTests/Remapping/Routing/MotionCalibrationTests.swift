import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

struct RemappingMotionCalibrationRoutingTests {
  @Test func calibrationAffectsOnlySelectedControllerAndReconnectStartsFresh() async throws {
    let harness = try await RemappingRouterHarness.make(profile: remappingRouterProfile())
    defer { harness.removeFiles() }
    let first = remappingRouterDevice(1)
    let second = remappingRouterDevice(2)
    for device in [first, second] {
      try await harness.router.dispatchCausally(events: [sample(0)], from: device)
    }
    let started = try await harness.router.motionCalibration(
      for: first.runtimeIdentifier, command: .start
    )
    #expect(started.isCollecting)
    try await harness.router.dispatchCausally(events: [sample(1)], from: first)
    let firstStatus = try await harness.router.motionCalibration(for: first.runtimeIdentifier)
    let secondStatus = try await harness.router.motionCalibration(for: second.runtimeIdentifier)
    #expect(firstStatus.offsetDegreesPerSecond.y == 3)
    #expect(!secondStatus.isCollecting && secondStatus.offsetDegreesPerSecond.y == 0)
    let paused = try await harness.router.motionCalibration(
      for: first.runtimeIdentifier, command: .pause
    )
    #expect(!paused.isCollecting && paused.offsetDegreesPerSecond.y == 3)
    try await harness.router.stopController(first)
    await #expect(throws: RemappingMotionCalibrationError.controllerUnavailable) {
      try await harness.router.motionCalibration(for: first.runtimeIdentifier, command: .start)
    }
    try await harness.router.dispatchCausally(events: [sample(0)], from: first)
    let reconnected = try await harness.router.motionCalibration(for: first.runtimeIdentifier)
    #expect(reconnected.hasMotionBaseline && !reconnected.isCollecting)
    #expect(reconnected.offsetDegreesPerSecond.y == 0)
    try await harness.router.shutdown()
  }

  private func sample(_ sequence: UInt64) -> ControllerEvent {
    .motionSample(ControllerMotionSample(
      timestamp: ControllerSampleTimestamp(
        rawCounter: 0,
        elapsedNanoseconds: sequence * 10_000_000,
        tickNanosecondsNumerator: nil,
        tickNanosecondsDenominator: nil,
        sequenceIndex: sequence,
        basis: .hostEstimate
      ),
      rawGyroscope: ControllerRawSensorVector(x: 0, y: 0, z: 0),
      rawAccelerometer: ControllerRawSensorVector(x: 0, y: 0, z: 0),
      physicalReading: ControllerMotionReading(
        gyroscopeDegreesPerSecond: ControllerMotionVector(x: 0, y: 3, z: 0),
        accelerationG: ControllerMotionVector(x: 0, y: 1, z: 0),
        calibrationSource: .nominalDeviceScale
      )
    ))
  }
}
