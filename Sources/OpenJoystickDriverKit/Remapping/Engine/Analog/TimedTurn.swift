import Foundation

/// One bounded trajectory, expressed in degrees before pointer or virtual-stick conversion.
struct RemappingTimedTurn {
  /// Angle to reach, in degrees.
  private var target = 0.0
  /// Angle already emitted, in degrees.
  private var emitted = 0.0
  /// Uptime at which the trajectory started, in nanoseconds.
  private var started: UInt64 = 0
  /// Time over which the trajectory runs, in nanoseconds.
  private var duration: UInt64 = 0
  /// Latest uptime seen, in nanoseconds.
  private var lastUptime: UInt64 = 0

  /// Whether part of the trajectory is still to be emitted.
  var isActive: Bool { target != emitted }

  /// Drops the trajectory.
  mutating func reset() {
    target = 0
    emitted = 0
    duration = 0
  }

  /// Adds a turn to the trajectory and returns the angle that falls due.
  ///
  /// The returned angle covers the trajectory before the turn plus the first step of the turn. The
  /// remaining movement is kept in one trajectory, so storage does not grow with input rate. A turn
  /// above 360 degrees, a duration above 10 s, or a remaining total above 3600 degrees resets the
  /// trajectory.
  mutating func append(degrees: Double, durationNanoseconds: UInt64, at uptime: UInt64) -> Double {
    guard degrees.isFinite, abs(degrees) <= 360, durationNanoseconds <= 10_000_000_000 else {
      reset()
      return 0
    }
    let due = advance(at: uptime)
    let combined = target - emitted + degrees
    guard combined.isFinite, abs(combined) <= 3600 else {
      reset()
      return due
    }
    target = combined
    emitted = 0
    started = lastUptime
    duration = durationNanoseconds
    return due + advance(at: lastUptime)
  }

  /// Returns the angle that falls due up to an uptime, eased along a smooth step.
  ///
  /// The trajectory clears itself once its duration has passed.
  mutating func advance(at uptime: UInt64) -> Double {
    lastUptime = max(lastUptime, uptime)
    guard isActive else { return 0 }
    let elapsed = lastUptime >= started ? lastUptime - started : 0
    let fraction = duration == 0 ? 1 : min(1, Double(elapsed) / Double(duration))
    let eased = fraction * fraction * (3 - 2 * fraction)
    let next = target * eased
    let delta = next - emitted
    emitted = next
    if fraction == 1 { reset() }
    return delta
  }
}
