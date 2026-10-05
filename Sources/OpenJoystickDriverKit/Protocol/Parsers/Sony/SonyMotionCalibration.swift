/// Independently implemented affine conversion from the Sony calibration report's endpoint facts.
/// Report layout and validation bounds are documented in docs/development/remapping.md.
struct SonyMotionCalibration {
  private enum Report {
    static let dualSenseLength = 41
    static let dualSenseID: UInt8 = 5
    static let dualShock4BluetoothLength = 41
    static let dualShock4BluetoothID: UInt8 = 5
    static let dualShock4USBLength = 37
    static let dualShock4USBID: UInt8 = 2
  }

  private static let nominalGyroCountsPerDegreePerSecond = 16.0
  private static let nominalAccelerometerCountsPerG = 8_192.0
  private static let maximumPlausibleBias = 1_024.0
  private static let plausibleScaleRange = 0.5...1.5

  private struct Axis: Equatable {
    let bias: Double
    let unitsPerCount: Double

    func apply(_ raw: Int16) -> Double { (Double(raw) - bias) * unitsPerCount }
  }

  private let gyro: [Axis]
  private let accel: [Axis]
  private var revision: UInt64 = 0
  private let source: ControllerMotionCalibrationSource

  static let nominal = Self(
    gyro: Array(
      repeating: Axis(bias: 0, unitsPerCount: 1.0 / nominalGyroCountsPerDegreePerSecond),
      count: 3
    ),
    accel: Array(
      repeating: Axis(bias: 0, unitsPerCount: 1.0 / nominalAccelerometerCountsPerG),
      count: 3
    ),
    source: .nominalDeviceScale
  )

  static func dualSenseFactory(_ bytes: [UInt8]) -> Self? {
    guard bytes.count == Report.dualSenseLength, bytes[0] == Report.dualSenseID else { return nil }
    return factory(bytes, groupedGyroEndpoints: false, useBiasedGyroRange: false)
  }

  /// `groupsGyroEndpoints` selects the Bluetooth gyro endpoint order (all plus, then all minus),
  /// which SDL `HIDAPI_DriverPS4_LoadCalibrationData` also reads from Sony's wireless adapter's
  /// USB report.
  static func dualShock4Factory(
    _ bytes: [UInt8],
    bluetooth: Bool,
    groupsGyroEndpoints: Bool
  ) -> Self? {
    let expectedLength = bluetooth ? Report.dualShock4BluetoothLength : Report.dualShock4USBLength
    let expectedID = bluetooth ? Report.dualShock4BluetoothID : Report.dualShock4USBID
    guard bytes.count == expectedLength, bytes[0] == expectedID else { return nil }
    return factory(bytes, groupedGyroEndpoints: groupsGyroEndpoints, useBiasedGyroRange: true)
  }

  /// This calibration with every gyro and accelerometer axis scale multiplied by a factor.
  func scaled(gyro gyroFactor: Double, accel accelFactor: Double) -> Self {
    var result = Self(
      gyro: gyro.map { Axis(bias: $0.bias, unitsPerCount: $0.unitsPerCount * gyroFactor) },
      accel: accel.map { Axis(bias: $0.bias, unitsPerCount: $0.unitsPerCount * accelFactor) },
      source: source
    )
    result.revision = revision
    return result
  }

  private static func factory(
    _ bytes: [UInt8],
    groupedGyroEndpoints: Bool,
    useBiasedGyroRange: Bool
  ) -> Self? {
    func value(_ offset: Int) -> Double {
      Double(Int16(bitPattern: UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)))
    }
    let speed = value(19) + value(21)
    var gyro: [Axis] = []
    var accel: [Axis] = []
    for index in 0..<3 {
      let gyroBias = value(1 + index * 2)
      let gyroPlus = value(7 + index * (groupedGyroEndpoints ? 2 : 4))
      let gyroMinus = value(groupedGyroEndpoints ? 13 + index * 2 : 9 + index * 4)
      let gyroRange =
        useBiasedGyroRange
        ? abs(gyroPlus - gyroBias) + abs(gyroMinus - gyroBias) : gyroPlus - gyroMinus
      let accelPlus = value(23 + index * 4)
      let accelMinus = value(25 + index * 4)
      let accelRange = accelPlus - accelMinus
      guard speed > 0, gyroRange > 0, accelRange > 0 else { return nil }
      let gyroGain = speed / gyroRange
      let accelGain = 2 / accelRange
      let accelBias = (accelPlus + accelMinus) / 2
      guard abs(gyroBias) <= maximumPlausibleBias, abs(accelBias) <= maximumPlausibleBias,
        plausibleScaleRange.contains(gyroGain * nominalGyroCountsPerDegreePerSecond),
        plausibleScaleRange.contains(accelGain * nominalAccelerometerCountsPerG)
      else { return nil }
      gyro.append(Axis(bias: gyroBias, unitsPerCount: gyroGain))
      accel.append(Axis(bias: accelBias, unitsPerCount: accelGain))
    }
    return Self(gyro: gyro, accel: accel, source: .deviceFactory)
  }

  func installed(after previous: Self) -> Self {
    var result = self
    let changed = gyro != previous.gyro || accel != previous.accel || source != previous.source
    result.revision = previous.revision &+ (changed ? 1 : 0)
    return result
  }

  /// DS4 and DualSense transform: raw counts, then factory (or nominal 1/16 °/s, 1/8192 g)
  /// calibration per axis, then SI, then raw (x, y, z) → canonical (x, -z, y).
  /// SDL passes the calibrated raw axes straight through as its sensor frame (X right, Y up,
  /// Z toward the player; `include/SDL3/SDL_sensor.h`): `HIDAPI_DriverPS4_HandleStatePacket` in
  /// `src/joystick/hidapi/SDL_hidapi_ps4.c` and `HIDAPI_DriverPS5_HandleStatePacketCommon` in
  /// `SDL_hidapi_ps5.c` at SDL `1ce4c5bc`. Linux `hid-playstation.c` `dualshock4_parse_report`
  /// and `dualsense_parse_report` likewise keep the wire axis order. The canonical frame takes
  /// SDL's +Z (toward the player) as -Y and SDL's +Y (up) as +Z.
  func sample(
    timestamp: ControllerSampleTimestamp,
    gyro rawGyro: ControllerRawSensorVector,
    accel rawAccel: ControllerRawSensorVector
  ) -> ControllerMotionSample? {
    ControllerMotionSample(
      timestamp: timestamp,
      canonicalDegreesPerSecond: ControllerMotionVector(
        x: gyro[0].apply(rawGyro.x),
        y: -gyro[2].apply(rawGyro.z),
        z: gyro[1].apply(rawGyro.y)
      ),
      canonicalG: ControllerMotionVector(
        x: accel[0].apply(rawAccel.x),
        y: -accel[2].apply(rawAccel.z),
        z: accel[1].apply(rawAccel.y)
      ),
      calibrationSource: source,
      calibrationRevision: revision
    )
  }
}
