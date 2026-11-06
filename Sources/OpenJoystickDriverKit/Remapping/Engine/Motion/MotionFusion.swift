import Foundation

/// Unit quaternion mapping the controller's local frame into the Y-up reference frame.
struct RemappingMotionQuaternion: Equatable {
  /// Scalar part.
  var w = 1.0
  /// X component of the vector part.
  var x = 0.0
  /// Y component of the vector part.
  var y = 0.0
  /// Z component of the vector part.
  var z = 0.0

  /// Conjugate, which is the inverse of a unit quaternion.
  var inverse: Self { Self(w: w, x: -x, y: -y, z: -z) }

  /// Returns the product with another quaternion, normalized to unit length.
  func multiplied(by rhs: Self) -> Self {
    let result = Self(
      w: w * rhs.w - x * rhs.x - y * rhs.y - z * rhs.z,
      x: w * rhs.x + x * rhs.w + y * rhs.z - z * rhs.y,
      y: w * rhs.y - x * rhs.z + y * rhs.w + z * rhs.x,
      z: w * rhs.z + x * rhs.y - y * rhs.x + z * rhs.w
    )
    let norm = sqrt(
      result.w * result.w + result.x * result.x + result.y * result.y + result.z * result.z
    )
    return Self(w: result.w / norm, x: result.x / norm, y: result.y / norm, z: result.z / norm)
  }

  /// Returns a vector rotated by the quaternion.
  func rotate(_ vector: SIMD3<Double>) -> SIMD3<Double> {
    let imaginary = SIMD3(x, y, z)
    let twiceCross = Self.cross(imaginary, vector) * 2
    return vector + twiceCross * w + Self.cross(imaginary, twiceCross)
  }

  /// Returns the rotation by an angle in radians about an axis.
  ///
  /// Returns the identity for an axis of near-zero length.
  static func rotation(axis: SIMD3<Double>, angle: Double) -> Self {
    let length = sqrt(axis.x * axis.x + axis.y * axis.y + axis.z * axis.z)
    guard length > 1e-12 else { return Self() }
    let scale = sin(angle / 2) / length
    return Self(w: cos(angle / 2), x: axis.x * scale, y: axis.y * scale, z: axis.z * scale)
  }

  /// Returns the rotation that turns a unit vector toward the Y axis by a fraction of the full
  /// angle.
  static func alignUp(_ vector: SIMD3<Double>, fraction: Double) -> Self {
    let dot = max(-1, min(1, vector.y))
    let axis = cross(vector, SIMD3(0, 1, 0))
    // At the antipode there is no unique heading; choose the local/reference X axis consistently.
    if dot < -0.999999999 { return rotation(axis: SIMD3(1, 0, 0), angle: .pi * fraction) }
    return rotation(axis: axis, angle: acos(dot) * fraction)
  }

  /// Returns the cross product of two vectors.
  private static func cross(_ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>) -> SIMD3<Double> {
    SIMD3(
      lhs.y * rhs.z - lhs.z * rhs.y,
      lhs.z * rhs.x - lhs.x * rhs.z,
      lhs.x * rhs.y - lhs.y * rhs.x
    )
  }
}

/// Orientation and gravity direction for one fused sample.
struct RemappingFusedMotion {
  /// Orientation in the reference frame.
  let orientation: RemappingMotionQuaternion
  /// Gravity in the controller's local frame, in standard gravities.
  let gravityG: ControllerMotionVector
}

/// Integrates the gyro and corrects tilt from the accelerometer.
///
/// Heading stays relative to the first heading and can drift.
struct RemappingMotionFusion {
  /// Current orientation, relative to the first heading.
  private(set) var orientation = RemappingMotionQuaternion()
  /// Whether a trusted gravity reading has set the orientation.
  private var initialized = false

  /// Returns to the state before the first sample.
  mutating func reset() { self = Self() }

  /// Integrates a sample and returns the fused result, or `nil` when it cannot be used.
  ///
  /// The sample is unusable when a value is not finite or out of range. Until the first trusted
  /// gravity reading sets the orientation, a reading with an acceleration magnitude outside 0.8 to
  /// 1.2 g is also unusable. After that, the gyro rotates the orientation and a trusted gravity
  /// reading pulls it toward the measured tilt. A `deltaTime` of zero skips both steps.
  /// - Parameters:
  ///   - gyro: Angular velocity in degrees per second.
  ///   - acceleration: Acceleration in standard gravities.
  ///   - deltaTime: Time since the previous sample in seconds, from 0 to 0.1.
  ///   - gravityCorrectionRate: Tilt correction rate per second, from 0 to 100.
  /// - Returns: The fused motion, or `nil` when the sample is unusable.
  mutating func update(
    gyro: ControllerMotionVector,
    acceleration: ControllerMotionVector,
    deltaTime: Double,
    gravityCorrectionRate: Double = 2
  ) -> RemappingFusedMotion? {
    guard gyro.isFinite, acceleration.isFinite, deltaTime.isFinite, gravityCorrectionRate.isFinite,
      (0...100).contains(gravityCorrectionRate), (0...0.1).contains(deltaTime),
      max(abs(gyro.x), abs(gyro.y), abs(gyro.z)) <= 1_000_000,
      max(abs(acceleration.x), abs(acceleration.y), abs(acceleration.z)) <= 1_000
    else { return nil }
    let gyroVector = SIMD3(gyro.x, gyro.y, gyro.z)
    let accel = SIMD3(acceleration.x, acceleration.y, acceleration.z)
    let magnitude = sqrt(accel.x * accel.x + accel.y * accel.y + accel.z * accel.z)
    let trustedGravity = (0.8...1.2).contains(magnitude)
    if !initialized {
      guard trustedGravity else { return nil }
      orientation = .alignUp(accel / magnitude, fraction: 1)
      initialized = true
    } else if deltaTime > 0 {
      let speed = sqrt(gyro.x * gyro.x + gyro.y * gyro.y + gyro.z * gyro.z)
      let rotation = RemappingMotionQuaternion.rotation(
        axis: gyroVector,
        angle: speed * .pi / 180 * deltaTime
      )
      orientation = orientation.multiplied(by: rotation)
      if trustedGravity {
        let referenceUp = orientation.rotate(accel / magnitude)
        let correction = RemappingMotionQuaternion.alignUp(
          referenceUp,
          fraction: 1 - exp(-gravityCorrectionRate * deltaTime)
        )
        orientation = correction.multiplied(by: orientation)
      }
    }
    let gravity = orientation.inverse.rotate(SIMD3(0, -1, 0))
    return RemappingFusedMotion(
      orientation: orientation,
      gravityG: ControllerMotionVector(x: gravity.x, y: gravity.y, z: gravity.z)
    )
  }
}
