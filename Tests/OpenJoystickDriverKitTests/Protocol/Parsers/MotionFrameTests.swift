import Testing

@testable import OpenJoystickDriverKit

/// One raw axis at a time through each driver's transform, so every canonical component and sign
/// is pinned: +X right, +Y away from the player, +Z up through the face; rotation by the
/// right-hand rule. Expected mappings are documented on each producer's `sample` function.
struct MotionFrameTests {
  private typealias Raw = ControllerRawSensorVector
  private static let timestamp = ControllerSampleTimestamp(
    rawCounter: 0,
    monotonic: MonotonicTimestamp(nanoseconds: 0),
    tickNanosecondsNumerator: nil,
    tickNanosecondsDenominator: nil,
    sequenceIndex: 0,
    basis: .hostEstimate
  )
  private static let zero = Raw(x: 0, y: 0, z: 0)

  /// Unit vectors along raw X, Y, Z with the canonical (x, y, z) each lands on.
  private static let axes: [(Raw, (Double, Double, Double))] = [
    (Raw(x: 1, y: 0, z: 0), (1, 0, 0)), (Raw(x: 0, y: 1, z: 0), (0, 1, 0)),
    (Raw(x: 0, y: 0, z: 1), (0, 0, 1)),
  ]

  @Test
  func sonyMapsRawAxesAsXMinusZY() throws {
    // Raw (x, y, z) → canonical (x, -z, y), 16 counts per °/s and 8192 counts per g.
    let expected: [(Double, Double, Double)] = [(1, 0, 0), (0, 0, 1), (0, -1, 0)]
    for (index, (raw, _)) in Self.axes.enumerated() {
      let scaled = Raw(x: raw.x * 16, y: raw.y * 16, z: raw.z * 16)
      let gyro = try #require(
        SonyMotionCalibration.nominal.sample(
          timestamp: Self.timestamp,
          gyro: scaled,
          accel: Self.zero
        )
      )
      let (x, y, z) = expected[index]
      #expect(isClose(gyro.angularVelocity, radiansPerSecond(x, y, z)))
      let accelRaw = Raw(x: raw.x * 8192, y: raw.y * 8192, z: raw.z * 8192)
      let accel = try #require(
        SonyMotionCalibration.nominal.sample(
          timestamp: Self.timestamp,
          gyro: Self.zero,
          accel: accelRaw
        )
      )
      #expect(isClose(accel.acceleration, metresPerSecondSquared(x, y, z)))
    }
  }

  @Test
  func dualShock4CaptureAtRestReadsGravityUpThroughTheFace() throws {
    // Captured owner DS4 lying face up (`capturedDualShock4` pin): raw accel (-17, 7784, 1792).
    let sample = try #require(
      SonyMotionCalibration.nominal.sample(
        timestamp: Self.timestamp,
        gyro: Self.zero,
        accel: Raw(x: -17, y: 7784, z: 1792)
      )
    )
    #expect(sample.acceleration.z > 9)
    #expect(abs(sample.acceleration.x) < 0.1)
    #expect(sample.acceleration.y < 0)
  }

  @Test(arguments: [NintendoControllerLayout.pro, .leftJoyCon, .rightJoyCon])
  func nintendoMapsRawAxesPerLayout(_ layout: NintendoControllerLayout) throws {
    // Pro and left Joy-Con: raw (x, y, z) → (-y, x, z). Right Joy-Con: → (y, x, -z).
    let right = layout == .rightJoyCon
    let expected: [(Double, Double, Double)] = [
      (0, 1, 0), (right ? 1 : -1, 0, 0), (0, 0, right ? -1 : 1),
    ]
    for (index, (raw, _)) in Self.axes.enumerated() {
      let accelRaw = Raw(x: raw.x * 4096, y: raw.y * 4096, z: raw.z * 4096)
      let sample = try #require(
        NintendoMotionCalibration.nominal.sample(
          timestamp: Self.timestamp,
          gyro: raw,
          accel: accelRaw,
          layout: layout
        )
      )
      let (x, y, z) = expected[index]
      let gyroScale = 1 / 14.2842
      #expect(
        isClose(
          sample.angularVelocity,
          radiansPerSecond(x * gyroScale, y * gyroScale, z * gyroScale)
        )
      )
      #expect(isClose(sample.acceleration, metresPerSecondSquared(x, y, z)))
    }
  }

  /// Pins SDL's Steam mapping, not a verified physical frame: gyro raw (x, y, z) → (x, -y, z) and
  /// accel raw (x, y, z) → (x, y, z), both at nominal full scale. The two differ by a reflection,
  /// so at most one is right-handed; handedness is hardware-unverified until a capture (right edge
  /// rolled down at rest, `docs/testing/steam-controller.md`) settles it.
  @Test
  func steamPinsSDLMappingWithUnverifiedHandedness() throws {
    let gyroSigns: [(Double, Double, Double)] = [(1, 0, 0), (0, -1, 0), (0, 0, 1)]
    for (index, (raw, accelAxis)) in Self.axes.enumerated() {
      let scaled = Raw(x: raw.x * 16_384, y: raw.y * 16_384, z: raw.z * 16_384)
      let sample = try #require(
        SteamMotionSamples.sample(timestamp: Self.timestamp, gyro: scaled, accel: scaled)
      )
      let (gx, gy, gz) = gyroSigns[index]
      #expect(isClose(sample.angularVelocity, radiansPerSecond(gx * 1000, gy * 1000, gz * 1000)))
      let (ax, ay, az) = accelAxis
      #expect(isClose(sample.acceleration, metresPerSecondSquared(ax, ay, az)))
    }
  }

  @Test
  func remappingEngineReadsTheSampleBackInItsDegreesAndGravitiesFrame() throws {
    // Canonical +Z (up) is the engine's +Y; canonical +Y (away) is the engine's -Z.
    let sample = try #require(
      ControllerMotionSample(
        timestamp: Self.timestamp,
        canonicalDegreesPerSecond: ControllerMotionVector(x: 10, y: 20, z: 30),
        canonicalG: ControllerMotionVector(x: 0.25, y: -0.5, z: 1),
        calibrationSource: .nominalDeviceScale
      )
    )
    let reading = RemappingMotionReading(sample)
    #expect(
      isClose(reading.gyroscopeDegreesPerSecond, ControllerMotionVector(x: 10, y: 30, z: -20))
    )
    #expect(isClose(reading.accelerationG, ControllerMotionVector(x: 0.25, y: 1, z: 0.5)))
  }
}
