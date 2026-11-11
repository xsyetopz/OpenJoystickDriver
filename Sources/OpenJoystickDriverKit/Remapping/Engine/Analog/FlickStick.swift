import Foundation

/// Tracks outward flicks and shortest-path rim rotation in clockwise degrees from forward.
///
/// Timing and output scaling belong to the shared output scheduler.
struct RemappingFlickStick {
  /// What a stick sample means for the flick tracker.
  enum Event: Equatable {
    /// The stick reached the rim at an angle.
    case flick(degrees: Double)
    /// The stick turned along the rim by an angle.
    case rotation(degrees: Double)
  }

  /// Rim angle at the previous sample, or `nil` while the stick is off the rim.
  private var previousAngle: Double?

  /// Forgets the rim angle.
  mutating func reset() { previousAngle = nil }

  /// Feeds a stick sample and returns a flick or a rim rotation.
  ///
  /// The first sample at or above `threshold` is a flick. Later samples stay on the rim while the
  /// deflection is at or above `threshold` minus `hysteresis`, and each gives the shortest rotation
  /// since the previous one, or `nil` when the angle did not change. Invalid parameters, or a
  /// sample off the rim, reset the tracker and return `nil`.
  mutating func process(
    x: Double,
    y: Double,
    threshold: Double = 0.9,
    hysteresis: Double = 0.1
  ) -> Event? {
    guard x.isFinite, y.isFinite, threshold.isFinite, hysteresis.isFinite,
      (0.1...1).contains(threshold), (0...0.5).contains(hysteresis), hysteresis < threshold
    else {
      reset()
      return nil
    }
    let clampedX = max(-1, min(1, x))
    let clampedY = max(-1, min(1, y))
    let magnitude = hypot(clampedX, clampedY)
    let required = previousAngle == nil ? threshold : threshold - hysteresis
    guard magnitude >= required else {
      reset()
      return nil
    }
    let angle = atan2(clampedX, -clampedY) * 180 / .pi
    defer { previousAngle = angle }
    guard let previousAngle else { return .flick(degrees: angle) }
    var delta = (angle - previousAngle).truncatingRemainder(dividingBy: 360)
    if delta > 180 { delta -= 360 }
    if delta < -180 { delta += 360 }
    return delta == 0 ? nil : .rotation(degrees: delta)
  }
}
