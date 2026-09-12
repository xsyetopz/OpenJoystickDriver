import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

struct JoyConPairingRoutingTests {
  @Test
  func exactHalvesCombineIntoOneOutputAndDisconnectReturnsTheSurvivorToCompatibility() async throws
  {
    let profile = pairProfile()
    let harness = try await RemappingRouterHarness.make()
    defer { harness.removeFiles() }
    try await harness.library.create(profile)
    let left = joyCon(productID: 0x2006, location: 1)
    let right = joyCon(productID: 0x2007, location: 2)
    for member in [left, right] {
      await harness.router.controllerInputOwnershipChanged(.exclusive, for: member)
      try await harness.router.dispatchCausally(events: [], from: member)
    }
    harness.recorder.removeAll()

    let sessionID = try await harness.router.pairJoyCons(
      leftRuntimeIdentifier: left.runtimeIdentifier,
      rightRuntimeIdentifier: right.runtimeIdentifier,
      profile: profile
    )
    try await harness.router.dispatchCausally(events: [.buttonPressed(.leftSL)], from: left)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: right)

    #expect(
      harness.recorder.snapshot().suffix(2) == [
        .gamepad(RemappingGamepadState(buttons: [.leftShoulder]), left),
        .gamepad(RemappingGamepadState(buttons: [.leftShoulder, .north]), left),
      ]
    )
    #expect(await harness.router.statusSnapshot().joyConPairs.map(\.sessionID) == [sessionID])

    harness.recorder.removeAll()
    try await harness.router.stopController(right)
    #expect(
      harness.recorder.snapshot().suffix(2) == [.gamepad(.neutral, left), .compatibilityStop(left)]
    )
    #expect(await harness.router.statusSnapshot().joyConPairs.isEmpty)
    #expect(await harness.router.status(for: left)?.selection == .compatibility)
    #expect(await harness.router.status(for: right) == nil)
    harness.recorder.removeAll()
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: right)
    #expect(harness.recorder.snapshot() == [.compatibility([.buttonPressed(.a)], right)])
    #expect(await harness.router.statusSnapshot().joyConPairs.isEmpty)
  }

  @Test
  func pairRequiresBothExactSidesAndRejectsAReusedSessionIdentifier() async throws {
    let profile = pairProfile()
    let harness = try await RemappingRouterHarness.make()
    defer { harness.removeFiles() }
    try await harness.library.create(profile)
    let left = joyCon(productID: 0x2006, location: 11)
    let right = joyCon(productID: 0x2007, location: 12)
    try await harness.router.dispatchCausally(events: [], from: left)
    await #expect(throws: RemappingJoyConPairError.controllerUnavailable) {
      _ = try await harness.router.pairJoyCons(
        leftRuntimeIdentifier: left.runtimeIdentifier,
        rightRuntimeIdentifier: right.runtimeIdentifier,
        profile: profile
      )
    }
    try await harness.router.dispatchCausally(events: [], from: right)
    let first = try await harness.router.pairJoyCons(
      leftRuntimeIdentifier: left.runtimeIdentifier,
      rightRuntimeIdentifier: right.runtimeIdentifier,
      profile: profile
    )
    try await harness.router.unpairJoyCons(first)
    let replacement = try await harness.router.pairJoyCons(
      leftRuntimeIdentifier: left.runtimeIdentifier,
      rightRuntimeIdentifier: right.runtimeIdentifier,
      profile: profile
    )
    await #expect(throws: RemappingJoyConPairError.sessionUnavailable) {
      try await harness.router.unpairJoyCons(first)
    }
    #expect(await harness.router.statusSnapshot().joyConPairs.map(\.sessionID) == [replacement])
  }

  @Test
  func selectedHalfAloneFeedsPairCalibrationAndTransactionCancelsTheSession() async throws {
    let profile = pairProfile(gyroSelection: .right)
    let harness = try await RemappingRouterHarness.make()
    defer { harness.removeFiles() }
    try await harness.library.create(profile)
    let left = joyCon(productID: 0x2006, location: 21)
    let right = joyCon(productID: 0x2007, location: 22)
    for member in [left, right] {
      await harness.router.controllerInputOwnershipChanged(.exclusive, for: member)
      try await harness.router.dispatchCausally(events: [], from: member)
    }
    _ = try await harness.router.pairJoyCons(
      leftRuntimeIdentifier: left.runtimeIdentifier,
      rightRuntimeIdentifier: right.runtimeIdentifier,
      profile: profile
    )
    try await harness.router.dispatchCausally(events: [motionSample()], from: left)
    await #expect(throws: RemappingMotionCalibrationError.motionUnavailable) {
      try await harness.router.motionCalibration(for: left.runtimeIdentifier)
    }
    try await harness.router.dispatchCausally(events: [motionSample()], from: right)
    #expect(
      try await harness.router.motionCalibration(for: right.runtimeIdentifier).hasMotionBaseline
    )

    let transaction = try await harness.router.beginProfileTransaction()
    #expect(await harness.router.statusSnapshot().joyConPairs.isEmpty)
    try await harness.router.rollBackProfileTransaction(transaction)
    #expect(await harness.router.status(for: left)?.selection == .compatibility)
    #expect(await harness.router.status(for: right)?.selection == .compatibility)
  }

  private func pairProfile(
    gyroSelection: RemappingJoyConGyroSelection = .disabled
  ) -> RemappingProfile {
    RemappingProfile(
      name: "Joy-Con pair",
      device: RemappingDeviceScope(vendorID: 0x057E, productID: 0x2006),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped, physicalInput: .exclusive),
      joyConPair: RemappingJoyConPairSettings(gyroSelection: gyroSelection),
      bindings: [
        RemappingBinding(source: .button(.leftSL), destination: .gamepadButton(.leftShoulder)),
        RemappingBinding(source: .button(.south), destination: .gamepadButton(.north)),
      ]
    )
  }

  private func joyCon(productID: UInt16, location: UInt32) -> DeviceIdentifier {
    DeviceIdentifier(vendorID: 0x057E, productID: productID, locationID: location)
  }

  private func motionSample() -> ControllerEvent {
    .motionSample(
      ControllerMotionSample(
        timestamp: ControllerSampleTimestamp(
          rawCounter: 1,
          elapsedNanoseconds: 10_000_000,
          tickNanosecondsNumerator: nil,
          tickNanosecondsDenominator: nil,
          sequenceIndex: 1,
          basis: .hostEstimate
        ),
        rawGyroscope: ControllerRawSensorVector(x: 0, y: 0, z: 0),
        rawAccelerometer: ControllerRawSensorVector(x: 0, y: 0, z: 0),
        physicalReading: ControllerMotionReading(
          gyroscopeDegreesPerSecond: ControllerMotionVector(x: 0, y: 1, z: 0),
          accelerationG: ControllerMotionVector(x: 0, y: 1, z: 0),
          calibrationSource: .nominalDeviceScale
        )
      )
    )
  }
}
