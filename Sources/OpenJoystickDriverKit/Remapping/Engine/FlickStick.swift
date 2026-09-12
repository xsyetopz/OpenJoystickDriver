import Foundation

/// Tracks outward flicks and shortest-path rim rotation in clockwise degrees from forward.
/// Timing and output scaling belong to the shared output scheduler.
struct RemappingFlickStick {
  enum Event: Equatable {
    case flick(degrees: Double)
    case rotation(degrees: Double)
  }

  private var previousAngle: Double?

  mutating func reset() { previousAngle = nil }

  mutating func process(
    x: Double, y: Double, threshold: Double = 0.9, hysteresis: Double = 0.1
  ) -> Event? {
    guard x.isFinite, y.isFinite, threshold.isFinite, hysteresis.isFinite,
      (0.1...1).contains(threshold), (0...0.5).contains(hysteresis), hysteresis < threshold
    else { reset(); return nil }
    let x = max(-1, min(1, x))
    let y = max(-1, min(1, y))
    let magnitude = hypot(x, y)
    let required = previousAngle == nil ? threshold : threshold - hysteresis
    guard magnitude >= required else { reset(); return nil }
    let angle = atan2(x, y) * 180 / .pi
    defer { previousAngle = angle }
    guard let previousAngle else { return .flick(degrees: angle) }
    var delta = (angle - previousAngle).truncatingRemainder(dividingBy: 360)
    if delta > 180 { delta -= 360 }
    if delta < -180 { delta += 360 }
    return delta == 0 ? nil : .rotation(degrees: delta)
  }
}
