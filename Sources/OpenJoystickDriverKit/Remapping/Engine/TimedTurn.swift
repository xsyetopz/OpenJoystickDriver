import Foundation

/// One bounded trajectory, expressed in degrees before pointer or virtual-stick conversion.
struct RemappingTimedTurn {
  private var target = 0.0
  private var emitted = 0.0
  private var started: UInt64 = 0
  private var duration: UInt64 = 0
  private var lastUptime: UInt64 = 0

  var isActive: Bool { target != emitted }

  mutating func reset() {
    target = 0
    emitted = 0
    duration = 0
  }

  /// Returns the old trajectory's newly due angle before appending another turn.
  /// Remaining movement is retained in one trajectory, so storage does not grow with input rate.
  mutating func append(degrees: Double, durationNanoseconds: UInt64, at uptime: UInt64) -> Double {
    guard degrees.isFinite, abs(degrees) <= 360, durationNanoseconds <= 10_000_000_000 else {
      reset()
      return 0
    }
    let due = advance(at: uptime)
    let combined = target - emitted + degrees
    guard combined.isFinite, abs(combined) <= 3600 else { reset(); return due }
    target = combined
    emitted = 0
    started = lastUptime
    duration = durationNanoseconds
    return due + advance(at: lastUptime)
  }

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
