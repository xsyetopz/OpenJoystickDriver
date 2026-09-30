/// Full Steam Controller state packets carry raw IMU vectors and a sequence number, not time.
/// Sample time is the first sample's receipt time plus the clamped receipt time elapsed since.
struct SteamMotionSamples {
  /// Where a state packet carries its IMU vectors and how its gyro maps to the canonical frame.
  enum Layout {
    /// `ValveControllerStatePacket_t`: accel at 28, gyro at 34, gyro Y reflected.
    case steamController
    /// `SteamDeckStatePacket_t`: accel at 24, gyro at 30, raw axes (see ``sample``).
    case steamDeck

    var accelOffset: Int { self == .steamController ? 28 : 24 }
    var gyroOffset: Int { accelOffset + 6 }
    var reflectsGyroY: Bool { self == .steamController }
  }

  private(set) var layout = Layout.steamController
  private var previousCounter: UInt32?
  private var firstReceipt: UInt64?
  private var elapsed: UInt64 = 0
  private var sequence: UInt64 = 0

  init(layout: Layout = .steamController) { self.layout = layout }

  /// Starts a new time and duplicate-tracking session; the sequence index keeps counting.
  mutating func reset() {
    let next = sequence
    self = Self(layout: layout)
    sequence = next
  }

  mutating func decode(_ bytes: [UInt8], receivedAt: UInt64) -> ControllerMotionSample? {
    guard bytes.count >= layout.gyroOffset + 6 else { return nil }
    let counter = UInt32(unsigned16(bytes, at: 4)) | (UInt32(unsigned16(bytes, at: 6)) << 16)
    guard previousCounter != counter else { return nil }
    previousCounter = counter
    let anchor = firstReceipt ?? receivedAt
    firstReceipt = anchor
    elapsed = max(elapsed, receivedAt >= anchor ? receivedAt - anchor : 0)
    let timestamp = ControllerSampleTimestamp(
      rawCounter: counter,
      monotonic: MonotonicTimestamp(nanoseconds: anchor + elapsed),
      tickNanosecondsNumerator: nil,
      tickNanosecondsDenominator: nil,
      sequenceIndex: sequence,
      basis: .hostEstimate
    )
    sequence += 1
    return Self.sample(
      timestamp: timestamp,
      gyro: vector(bytes, at: layout.gyroOffset),
      accel: vector(bytes, at: layout.accelOffset),
      reflectsGyroY: layout.reflectsGyroY
    )
  }

  /// Steam Controller transform: raw counts, nominal scale (no factory calibration is read), SI,
  /// then gyro (x, y, z) → (x, -y, z) and accel (x, y, z) → (x, y, z).
  /// Source: SDL `HIDAPI_DriverSteam_UpdateDevice` in `src/joystick/hidapi/SDL_hidapi_steam.c` at
  /// SDL `1ce4c5bc` scales gyro by 2000 °/s and accel by 2 g per 32768 counts and maps them into
  /// its sensor frame (X right, Y up, Z toward the player) as gyro (x, z, y) and accel (x, z, -y).
  /// The canonical frame takes SDL's +Z (toward the player) as -Y and SDL's +Y (up) as +Z.
  /// Linux `hid-steam.c` `steam_controller_imu_mappings` (used by `steam_do_sensors_event`) at
  /// Linux `fd179f8a` maps the same bytes the same way: accel rows `ABS_X` +28, `ABS_Z` -30,
  /// `ABS_Y` +32, i.e. (x, z, -y); gyro rows `ABS_RX` +34, `ABS_RZ` +36, `ABS_RY` +38, i.e.
  /// (x, z, y). Both sources give gyro and accel mappings that differ by a reflection of Y, so at
  /// most one is right-handed; it is kept until hardware confirms it. Linux's accel resolution
  /// (`STEAM_ACCEL_RES_PER_G` 16384) matches SDL's 2 g per 32768 counts. Linux declares 16 counts
  /// per °/s (`STEAM_GYRO_RES_PER_DPS`) where SDL uses 16.384; the SDL scale is kept.
  ///
  /// The Steam Deck packet puts accel at 24 and gyro at 30 with the same scales, and SDL
  /// `HIDAPI_DriverSteamDeck_HandleState` maps both gyro and accel as (x, z, -y), so the canonical
  /// frame equals the raw axes for both.
  static func sample(
    timestamp: ControllerSampleTimestamp,
    gyro: ControllerRawSensorVector,
    accel: ControllerRawSensorVector,
    reflectsGyroY: Bool = true
  ) -> ControllerMotionSample? {
    let gyroScale = 2000.0 / 32768
    let accelScale = 2.0 / 32768
    return ControllerMotionSample(
      timestamp: timestamp,
      canonicalDegreesPerSecond: ControllerMotionVector(
        x: Double(gyro.x) * gyroScale,
        y: (reflectsGyroY ? -1 : 1) * Double(gyro.y) * gyroScale,
        z: Double(gyro.z) * gyroScale
      ),
      canonicalG: ControllerMotionVector(
        x: Double(accel.x) * accelScale,
        y: Double(accel.y) * accelScale,
        z: Double(accel.z) * accelScale
      ),
      calibrationSource: .nominalDeviceScale
    )
  }

  private func unsigned16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
    UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
  }

  private func vector(_ bytes: [UInt8], at offset: Int) -> ControllerRawSensorVector {
    ControllerRawSensorVector(
      x: Int16(bitPattern: unsigned16(bytes, at: offset)),
      y: Int16(bitPattern: unsigned16(bytes, at: offset + 2)),
      z: Int16(bitPattern: unsigned16(bytes, at: offset + 4))
    )
  }
}
