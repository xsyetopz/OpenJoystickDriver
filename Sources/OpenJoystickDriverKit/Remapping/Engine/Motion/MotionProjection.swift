// Player/world projection adapted from GamepadMotionHelpers, Copyright (c) 2020-2023
// Julian "Jibb" Smart. MIT license; see THIRD_PARTY_NOTICES.md for the complete notice.
import Foundation

/// Gyro rotation rate projected onto pitch and yaw.
struct RemappingGyroProjection: Equatable {
  /// Pitch rate in degrees per second.
  let pitchDegreesPerSecond: Double
  /// Yaw rate in degrees per second.
  let yawDegreesPerSecond: Double
}

/// Projects a gyro vector onto pitch and yaw for a motion space.
enum RemappingMotionProjection {
  /// Returns the pitch and yaw rates of a gyro vector, or `nil` for input that is not finite or out
  /// of range.
  ///
  /// The local space reads pitch from X and yaw from Y. The player space takes yaw about gravity
  /// from the Y and Z rates, scaled by `yawRelaxation` and limited by the combined Y and Z rate.
  /// The world space projects the rate onto the controller's X axis made perpendicular to gravity
  /// for pitch, and onto gravity for yaw. In the world space, pitch is zero while the larger Y or Z
  /// gravity component is at or below `sideReductionThreshold`, and full from twice that.
  static func project(
    _ gyro: ControllerMotionVector,
    gravity: ControllerMotionVector,
    space: RemappingMotionSpace,
    yawRelaxation: Double = 1.41,
    sideReductionThreshold: Double = 0.125
  ) -> RemappingGyroProjection? {
    guard gyro.isFinite, max(abs(gyro.x), abs(gyro.y), abs(gyro.z)) <= 1_000_000,
      yawRelaxation.isFinite, (0...10).contains(yawRelaxation), sideReductionThreshold.isFinite,
      (0...1).contains(sideReductionThreshold)
    else { return nil }
    if space == .local {
      return RemappingGyroProjection(pitchDegreesPerSecond: gyro.x, yawDegreesPerSecond: gyro.y)
    }
    guard gravity.isFinite, max(abs(gravity.x), abs(gravity.y), abs(gravity.z)) <= 1_000 else {
      return nil
    }
    let length = sqrt(gravity.x * gravity.x + gravity.y * gravity.y + gravity.z * gravity.z)
    guard length > 1e-9 else { return nil }
    let gx = gravity.x / length
    let gy = gravity.y / length
    let gz = gravity.z / length
    if space == .player {
      let yaw = -(gy * gyro.y + gz * gyro.z)
      let magnitude = min(abs(yaw) * yawRelaxation, sqrt(gyro.y * gyro.y + gyro.z * gyro.z))
      return RemappingGyroProjection(
        pitchDegreesPerSecond: gyro.x,
        yawDegreesPerSecond: yaw < 0 ? -magnitude : magnitude
      )
    }
    let pitchAxis = SIMD3(1 - gx * gx, -gy * gx, -gz * gx)
    let pitchLength = sqrt(
      pitchAxis.x * pitchAxis.x + pitchAxis.y * pitchAxis.y + pitchAxis.z * pitchAxis.z
    )
    let reduction =
      sideReductionThreshold == 0
      ? 1
      : max(0, min(1, (max(abs(gy), abs(gz)) - sideReductionThreshold) / sideReductionThreshold))
    let pitch =
      pitchLength > 1e-9
      ? reduction * (pitchAxis.x * gyro.x + pitchAxis.y * gyro.y + pitchAxis.z * gyro.z)
        / pitchLength : 0
    return RemappingGyroProjection(
      pitchDegreesPerSecond: pitch,
      yawDegreesPerSecond: -(gx * gyro.x + gy * gyro.y + gz * gyro.z)
    )
  }
}
