import Foundation

/// Output of one stick runtime step.
struct RemappingStickRuntimeOutput: Equatable {
  /// Pointer displacement to emit.
  var pointerDelta = SIMD2<Double>.zero
  /// Scroll displacement to emit, in lines.
  var scrollLines = SIMD2<Double>.zero
  /// Virtual gamepad axis values to emit.
  var virtualAxes: [RemappingAxis: Double] = [:]

  /// Output with no movement.
  static let zero = Self()
}

/// Runtime of one stick of one controller.
///
/// Angular state and output ownership last for one mapping session.
struct RemappingStickRuntime {
  /// Mapping that the runtime follows.
  let mapping: RemappingStickMapping
  /// Owner identity of this stick's contribution to the virtual gamepad.
  let bindingID = UUID()
  /// Calibrated stick position.
  private var value = SIMD2<Double>.zero
  /// Pointer offset from its anchor that the pointer area and pointer ring modes hold.
  private var previousTarget = SIMD2<Double>.zero
  /// Stick angle at the previous sample in radians, or `nil` while the stick is centered.
  private var previousAngle: Double?
  /// Rim rotation that has not yet added up to a scroll line, in degrees.
  private var scrollRemainderDegrees = 0.0
  /// Accumulated steering wheel rotation, in degrees.
  private var steeringDegrees = 0.0
  /// Uptime of the last update or advance, in nanoseconds.
  private var lastUptime: UInt64?
  /// Flick and rim rotation tracker.
  private var flick = RemappingFlickStick()
  /// Trajectory that spreads a flick over its duration.
  private var turn = RemappingTimedTurn()

  /// Creates a runtime for a mapping.
  init(mapping: RemappingStickMapping) { self.mapping = mapping }

  /// Whether output still changes with time.
  ///
  /// That is the case during a running flick turn, while an aim stick is held off center, and while
  /// steering still returns to center.
  var needsTicks: Bool {
    turn.isActive
      || (mapping.mode == .aim && value != .zero && mapping.aimDegreesPerSecond > 0
        && mapping.pointerPointsPerDegree > 0)
      || (mapping.mode == .steering && steeringDegrees != 0 && value.length < 1
        && mapping.steeringReturnDegreesPerSecond > 0)
  }

  /// Clears all angular state.
  mutating func reset() {
    value = .zero
    previousTarget = .zero
    previousAngle = nil
    scrollRemainderDegrees = 0
    steeringDegrees = 0
    flick.reset()
    turn.reset()
    lastUptime = nil
  }

  /// Feeds a stick sample and returns the output it causes.
  ///
  /// A mapping that does not validate, or a non-finite sample, resets the runtime and returns the
  /// output that cancels what the mapping held.
  mutating func update(x: Double, y: Double, at uptime: UInt64) -> RemappingStickRuntimeOutput {
    guard (try? mapping.validate()) != nil,
      let next = RemappingStickTransform.value(x: x, y: y, tuning: mapping.tuning)
    else {
      let output = neutralizingOutput()
      reset()
      return output
    }
    var output = advance(at: uptime)
    let previousValue = value
    value = next
    switch mapping.mode {
    case .aim: break
    case .flick, .flickOnly, .rotateOnly:
      let event = flick.process(
        x: next.x,
        y: next.y,
        threshold: mapping.flickThreshold,
        hysteresis: mapping.flickHysteresis
      )
      let degrees: Double
      switch event {
      case .flick(let angle) where mapping.mode != .rotateOnly:
        degrees = turn.append(
          degrees: angle,
          durationNanoseconds: UInt64((mapping.flickDurationMs * 1_000_000).rounded()),
          at: lastUptime ?? uptime
        )
      case .rotation(let angle) where mapping.mode != .flickOnly: degrees = angle
      default: degrees = 0
      }
      output.pointerDelta.x += degrees * mapping.pointerPointsPerDegree
    case .pointerArea:
      let target = next * mapping.pointerRadiusPoints
      output.pointerDelta += target - previousTarget
      previousTarget = target
    case .pointerRing:
      let target =
        next == .zero ? .zero : next / next.length * mapping.pointerRadiusPoints
      output.pointerDelta += target - previousTarget
      previousTarget = target
    case .scrollWheel: output.scrollLines += scrollOutput(previous: previousValue, current: next)
    case .steering:
      updateSteering(previous: previousValue, current: next)
      output.virtualAxes[mapping.steeringOutput.axis] = steeringValue
    }
    return output
  }

  /// Advances time-based output to an uptime and returns it.
  ///
  /// Covers aim movement, the steering return and a running flick turn. The elapsed time is capped
  /// at 100 ms, so a long gap does not jump the output.
  mutating func advance(at uptime: UInt64) -> RemappingStickRuntimeOutput {
    let now = max(lastUptime ?? uptime, uptime)
    let elapsed = lastUptime.map { min(now - $0, 100_000_000) } ?? 0
    lastUptime = now
    var output = RemappingStickRuntimeOutput.zero
    if mapping.mode == .aim {
      let scale =
        Double(elapsed) / 1_000_000_000 * mapping.aimDegreesPerSecond
        * mapping.pointerPointsPerDegree
      output.pointerDelta = value * scale
    } else if mapping.mode == .steering {
      if value.length < 1, steeringDegrees != 0 {
        let amount =
          mapping.steeringReturnDegreesPerSecond * Double(elapsed) / 1_000_000_000
          * max(0, 1 - value.length)
        steeringDegrees = Self.approachZero(steeringDegrees, by: amount)
      }
      output.virtualAxes[mapping.steeringOutput.axis] = steeringValue
    } else {
      output.pointerDelta.x = turn.advance(at: now) * mapping.pointerPointsPerDegree
    }
    return output
  }

  /// Returns the scroll lines for the rim rotation since the previous sample.
  ///
  /// The part of a rotation under one line carries over to the next sample.
  private mutating func scrollOutput(
    previous: SIMD2<Double>,
    current: SIMD2<Double>
  ) -> SIMD2<Double> {
    guard current != .zero else {
      previousAngle = nil
      return .zero
    }
    let angle = atan2(-current.y, current.x)
    defer { previousAngle = angle }
    guard let oldAngle = previousAngle, previous != .zero else { return .zero }
    let delta =
      Self.shortestAngle(from: oldAngle, to: angle) * 180 / .pi
      * mapping.rotationDirection.multiplier
    scrollRemainderDegrees += delta
    let lines = (scrollRemainderDegrees / mapping.scrollDegreesPerLine).rounded(.towardZero)
    scrollRemainderDegrees -= lines * mapping.scrollDegreesPerLine
    switch mapping.scrollAxis {
    case .horizontal: return SIMD2(lines, 0)
    case .vertical: return SIMD2(0, lines)
    }
  }

  /// Adds the rim rotation since the previous sample to the steering angle.
  ///
  /// The rotation is weighted by the deflection and the angle is clamped to the full-scale angle.
  private mutating func updateSteering(previous: SIMD2<Double>, current: SIMD2<Double>) {
    guard previous != .zero, current != .zero else { return }
    let oldAngle = atan2(-previous.y, previous.x)
    let angle = atan2(-current.y, current.x)
    let delta =
      Self.shortestAngle(from: oldAngle, to: angle) * 180 / .pi * current.length
      * mapping.rotationDirection.multiplier
    steeringDegrees = min(
      mapping.steeringDegreesAtFullScale,
      max(-mapping.steeringDegreesAtFullScale, steeringDegrees + delta)
    )
  }

  /// Steering angle as a fraction of the full-scale angle.
  private var steeringValue: Double { steeringDegrees / mapping.steeringDegreesAtFullScale }

  /// Returns the output that cancels what the mapping holds.
  ///
  /// The pointer returns to its anchor in the pointer area and pointer ring modes, and steering
  /// returns to center.
  private func neutralizingOutput() -> RemappingStickRuntimeOutput {
    var output = RemappingStickRuntimeOutput.zero
    if mapping.mode == .pointerArea || mapping.mode == .pointerRing {
      output.pointerDelta = -previousTarget
    }
    if mapping.mode == .steering { output.virtualAxes[mapping.steeringOutput.axis] = 0 }
    return output
  }

  /// Returns the signed angle from `start` to `end` in radians, within -pi to pi.
  private static func shortestAngle(from start: Double, to end: Double) -> Double {
    var delta = (end - start).truncatingRemainder(dividingBy: 2 * .pi)
    if delta > .pi { delta -= 2 * .pi }
    if delta < -.pi { delta += 2 * .pi }
    return delta
  }

  /// Moves a value toward zero by an amount without crossing zero.
  private static func approachZero(_ value: Double, by amount: Double) -> Double {
    guard amount > 0 else { return value }
    if value > 0 { return max(0, value - amount) }
    return min(0, value + amount)
  }
}

extension SIMD2 where Scalar == Double {
  /// The Euclidean length of the stick vector.
  fileprivate var length: Double { hypot(x, y) }
}
