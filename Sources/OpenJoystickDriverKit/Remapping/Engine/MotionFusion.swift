import Foundation

/// Unit quaternion mapping the controller's local frame into the Y-up reference frame.
struct RemappingMotionQuaternion: Equatable {
  var w = 1.0
  var x = 0.0
  var y = 0.0
  var z = 0.0

  var inverse: Self { Self(w: w, x: -x, y: -y, z: -z) }

  func multiplied(by rhs: Self) -> Self {
    let result = Self(
      w: w * rhs.w - x * rhs.x - y * rhs.y - z * rhs.z,
      x: w * rhs.x + x * rhs.w + y * rhs.z - z * rhs.y,
      y: w * rhs.y - x * rhs.z + y * rhs.w + z * rhs.x,
      z: w * rhs.z + x * rhs.y - y * rhs.x + z * rhs.w
    )
    let norm = sqrt(result.w * result.w + result.x * result.x
      + result.y * result.y + result.z * result.z)
    return Self(w: result.w / norm, x: result.x / norm, y: result.y / norm, z: result.z / norm)
  }

  func rotate(_ vector: SIMD3<Double>) -> SIMD3<Double> {
    let imaginary = SIMD3(x, y, z)
    let twiceCross = Self.cross(imaginary, vector) * 2
    return vector + twiceCross * w + Self.cross(imaginary, twiceCross)
  }

  static func rotation(axis: SIMD3<Double>, angle: Double) -> Self {
    let length = sqrt(axis.x * axis.x + axis.y * axis.y + axis.z * axis.z)
    guard length > 1e-12 else { return Self() }
    let scale = sin(angle / 2) / length
    return Self(w: cos(angle / 2), x: axis.x * scale, y: axis.y * scale, z: axis.z * scale)
  }

  static func alignUp(_ vector: SIMD3<Double>, fraction: Double) -> Self {
    let dot = max(-1, min(1, vector.y))
    let axis = cross(vector, SIMD3(0, 1, 0))
    // At the antipode there is no unique heading; choose the local/reference X axis consistently.
    if dot < -0.999999999 { return rotation(axis: SIMD3(1, 0, 0), angle: .pi * fraction) }
    return rotation(axis: axis, angle: acos(dot) * fraction)
  }

  private static func cross(_ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>) -> SIMD3<Double> {
    SIMD3(
      lhs.y * rhs.z - lhs.z * rhs.y,
      lhs.z * rhs.x - lhs.x * rhs.z,
      lhs.x * rhs.y - lhs.y * rhs.x
    )
  }
}

struct RemappingFusedMotion {
  let orientation: RemappingMotionQuaternion
  let gravityG: ControllerMotionVector
  let linearAccelerationG: ControllerMotionVector
}

/// Gyro integration with accelerometer tilt correction; heading remains relative and can drift.
struct RemappingMotionFusion {
  private(set) var orientation = RemappingMotionQuaternion()
  private var initialized = false

  mutating func reset() { self = Self() }

  mutating func update(
    gyro: ControllerMotionVector,
    acceleration: ControllerMotionVector,
    deltaTime: Double,
    gravityCorrectionRate: Double = 2
  ) -> RemappingFusedMotion? {
    guard gyro.isFinite, acceleration.isFinite, deltaTime.isFinite,
      gravityCorrectionRate.isFinite, (0...100).contains(gravityCorrectionRate),
      (0...0.1).contains(deltaTime),
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
        axis: gyroVector, angle: speed * .pi / 180 * deltaTime
      )
      orientation = orientation.multiplied(by: rotation)
      if trustedGravity {
        let referenceUp = orientation.rotate(accel / magnitude)
        let correction = RemappingMotionQuaternion.alignUp(
          referenceUp, fraction: 1 - exp(-gravityCorrectionRate * deltaTime)
        )
        orientation = correction.multiplied(by: orientation)
      }
    }
    let gravity = orientation.inverse.rotate(SIMD3(0, -1, 0))
    let linear = accel + gravity
    return RemappingFusedMotion(
      orientation: orientation,
      gravityG: ControllerMotionVector(x: gravity.x, y: gravity.y, z: gravity.z),
      linearAccelerationG: ControllerMotionVector(x: linear.x, y: linear.y, z: linear.z)
    )
  }
}
