import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct MotionCalibrationActorTests {
  @Test func calibrationHonorsAdmissionAndReleaseWithoutEmittingOutput() async throws {
    let sink = RemappingTestSink()
    let engine = RemappingEventEngine(sink: sink)
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 3)
    let profile = RemappingProfile(
      name: "Calibration",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: []
    )
    await #expect(throws: RemappingMotionCalibrationError.controllerUnavailable) {
      try await engine.calibrateMotion(.start, for: identifier)
    }
    try await engine.setProfile(profile, for: identifier)
    await #expect(throws: RemappingMotionCalibrationError.motionUnavailable) {
      try await engine.calibrateMotion(.start, for: identifier)
    }
    let sample = ControllerMotionSample(
      timestamp: ControllerSampleTimestamp(
        rawCounter: 0,
        elapsedNanoseconds: 0,
        tickNanosecondsNumerator: nil,
        tickNanosecondsDenominator: nil,
        sequenceIndex: 0,
        basis: .hostEstimate
      ),
      rawGyroscope: ControllerRawSensorVector(x: 0, y: 0, z: 0),
      rawAccelerometer: ControllerRawSensorVector(x: 0, y: 0, z: 0),
      physicalReading: ControllerMotionReading(
        gyroscopeDegreesPerSecond: ControllerMotionVector(x: 0, y: 0, z: 0),
        accelerationG: ControllerMotionVector(x: 0, y: 1, z: 0),
        calibrationSource: .nominalDeviceScale
      )
    )
    try await engine.process(
      events: [.motionSample(sample)], from: identifier, using: profile, at: 0
    )
    let started = try await engine.calibrateMotion(.start, for: identifier)
    #expect(started.hasMotionBaseline && started.isCollecting)
    let oldPermit = try #require(engine.emissionBarrier.currentPermit())
    let owner = UUID()
    _ = await engine.emissionBarrier.suspend(owner: owner)
    await #expect(throws: RemappingEventEngineError.outputSuspended) {
      try await engine.calibrateMotion(.reset, for: identifier)
    }
    #expect(await engine.motionCalibrationStatus(for: identifier)?.isCollecting == true)
    #expect(engine.emissionBarrier.resume(owner: owner))
    await #expect(throws: RemappingEventEngineError.outputSuspended) {
      try await engine.calibrateMotion(.reset, for: identifier, requiring: oldPermit)
    }
    #expect(await engine.motionCalibrationStatus(for: identifier)?.isCollecting == true)
    let paused = try await engine.calibrateMotion(.pause, for: identifier)
    #expect(!paused.isCollecting && paused.hasMotionBaseline)
    let reset = try await engine.calibrateMotion(.reset, for: identifier)
    #expect(!reset.hasMotionBaseline)
    let previousSession = try #require(await engine.motionSessionIdentifier(for: identifier))
    try await engine.releaseAll(for: identifier)
    #expect(await engine.motionCalibrationStatus(for: identifier) == nil)
    try await engine.process(
      events: [.motionSample(sample)], from: identifier, using: profile, at: 0
    )
    let currentSession = try #require(await engine.motionSessionIdentifier(for: identifier))
    #expect(currentSession != previousSession)
    let currentPermit = try #require(engine.emissionBarrier.currentPermit())
    await #expect(throws: RemappingMotionCalibrationError.controllerUnavailable) {
      try await engine.calibrateMotion(
        .reset, for: identifier, requiring: currentPermit, expectedSessionID: previousSession
      )
    }
    #expect(await engine.motionCalibrationStatus(for: identifier)?.hasMotionBaseline == true)
    let freshReset = try await engine.calibrateMotion(
      .reset, for: identifier, requiring: currentPermit, expectedSessionID: currentSession
    )
    #expect(!freshReset.hasMotionBaseline)
    #expect(sink.actions().isEmpty)
  }
}
