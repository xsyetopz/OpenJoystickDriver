import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

struct JoyConPairingRoutingTests {
  @Test
  func exactHalvesCombineIntoOneOutputAndDisconnectReturnsTheSurvivorToVirtualGamepad() async throws
  {
    let profile = pairProfile()
    let harness = try await RemappingRouterHarness.make()
    defer { harness.removeFiles() }
    try await harness.library.create(profile)
    let left = joyCon(productID: 0x2006, location: 1)
    let right = joyCon(productID: 0x2007, location: 2)
    for member in [left, right] {
      await harness.router.controllerInputOwnershipChanged(.exclusive, for: member)
      try await harness.router.dispatchCausally(.activation, from: member)
    }
    harness.recorder.removeAll()

    let sessionID = try await harness.router.pairJoyCons(
      leftRuntimeIdentifier: left.runtimeIdentifier,
      rightRuntimeIdentifier: right.runtimeIdentifier,
      profile: profile
    )
    try await harness.router.dispatchCausally(changes: [.press(.auxiliary3)], from: left)
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: right)

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
      harness.recorder.snapshot().suffix(2) == [.gamepad(.neutral, left), .virtualOutputStop(left)]
    )
    #expect(await harness.router.statusSnapshot().joyConPairs.isEmpty)
    #expect(await harness.router.status(for: left)?.selection == .virtualGamepad)
    #expect(await harness.router.status(for: right) == nil)
    harness.recorder.removeAll()
    // The stopped half reconnects with a fresh pipeline, whose first snapshot holds South.
    InputScript.of(harness.router).reset(right)
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: right)
    #expect(
      harness.recorder.snapshot() == [
        .virtualGamepad(ControllerState.neutral.applying([.press(.faceSouth)]), right)
      ]
    )
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
    try await harness.router.dispatchCausally(.activation, from: left)
    await #expect(throws: RemappingJoyConPairError.controllerUnavailable) {
      _ = try await harness.router.pairJoyCons(
        leftRuntimeIdentifier: left.runtimeIdentifier,
        rightRuntimeIdentifier: right.runtimeIdentifier,
        profile: profile
      )
    }
    try await harness.router.dispatchCausally(.activation, from: right)
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
  func switch2HalvesPairAndSwappedSidesAreRejected() async throws {
    let profile = pairProfile()
    let harness = try await RemappingRouterHarness.make()
    defer { harness.removeFiles() }
    try await harness.library.create(profile)
    let left = joyCon(productID: 0x2067, location: 41)
    let right = joyCon(productID: 0x2066, location: 42)
    for member in [left, right] {
      try await harness.router.dispatchCausally(.activation, from: member)
    }
    await #expect(throws: RemappingJoyConPairError.invalidControllerSide) {
      _ = try await harness.router.pairJoyCons(
        leftRuntimeIdentifier: right.runtimeIdentifier,
        rightRuntimeIdentifier: left.runtimeIdentifier,
        profile: profile
      )
    }
    let sessionID = try await harness.router.pairJoyCons(
      leftRuntimeIdentifier: left.runtimeIdentifier,
      rightRuntimeIdentifier: right.runtimeIdentifier,
      profile: profile
    )
    #expect(await harness.router.statusSnapshot().joyConPairs.map(\.sessionID) == [sessionID])
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
      try await harness.router.dispatchCausally(.activation, from: member)
    }
    _ = try await harness.router.pairJoyCons(
      leftRuntimeIdentifier: left.runtimeIdentifier,
      rightRuntimeIdentifier: right.runtimeIdentifier,
      profile: profile
    )
    try await harness.router.dispatchCausally(changes: [gyroMotion()], from: left)
    await #expect(throws: RemappingMotionCalibrationError.motionUnavailable) {
      try await harness.router.motionCalibration(for: left.runtimeIdentifier)
    }
    try await harness.router.dispatchCausally(changes: [gyroMotion()], from: right)
    #expect(
      try await harness.router.motionCalibration(for: right.runtimeIdentifier).hasMotionBaseline
    )

    let transaction = try await harness.router.beginProfileTransaction()
    #expect(await harness.router.statusSnapshot().joyConPairs.isEmpty)
    try await harness.router.rollBackProfileTransaction(transaction)
    #expect(await harness.router.status(for: left)?.selection == .virtualGamepad)
    #expect(await harness.router.status(for: right)?.selection == .virtualGamepad)
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

  private func gyroMotion() -> InputChange {
    .motion(
      ControllerMotionSample.engineSpace(
        timestamp: ControllerSampleTimestamp(
          rawCounter: 1,
          monotonic: MonotonicTimestamp(nanoseconds: 10_000_000),
          tickNanosecondsNumerator: nil,
          tickNanosecondsDenominator: nil,
          sequenceIndex: 1,
          basis: .hostEstimate
        ),
        gyroDegreesPerSecond: ControllerMotionVector(x: 0, y: 1, z: 0),
        accelerationG: ControllerMotionVector(x: 0, y: 1, z: 0),
        calibrationSource: .nominalDeviceScale
      )
    )
  }
}
