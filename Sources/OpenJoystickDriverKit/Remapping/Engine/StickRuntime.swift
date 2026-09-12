import Foundation

struct RemappingStickRuntimeOutput: Equatable {
  var pointerDelta = SIMD2<Double>.zero
  var scrollLines = SIMD2<Double>.zero
  var virtualAxes: [RemappingAxis: Double] = [:]

  static let zero = Self()
}

/// One controller's one stick. Angular state and output ownership live for one mapping session.
struct RemappingStickRuntime {
  let mapping: RemappingStickMapping
  let bindingID = UUID()
  private var value = SIMD2<Double>.zero
  private var previousTarget = SIMD2<Double>.zero
  private var previousAngle: Double?
  private var scrollRemainderDegrees = 0.0
  private var steeringDegrees = 0.0
  private var lastUptime: UInt64?
  private var flick = RemappingFlickStick()
  private var turn = RemappingTimedTurn()

  init(mapping: RemappingStickMapping) { self.mapping = mapping }

  var needsTicks: Bool {
    turn.isActive
      || (mapping.mode == .aim && value != .zero
        && mapping.aimDegreesPerSecond > 0 && mapping.pointerPointsPerDegree > 0)
      || (mapping.mode == .steering && steeringDegrees != 0 && value.length < 1
        && mapping.steeringReturnDegreesPerSecond > 0)
  }

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
      let target = SIMD2(next.x, -next.y) * mapping.pointerRadiusPoints
      output.pointerDelta += target - previousTarget
      previousTarget = target
    case .pointerRing:
      let target =
        next == .zero
        ? .zero : SIMD2(next.x, -next.y) / next.length * mapping.pointerRadiusPoints
      output.pointerDelta += target - previousTarget
      previousTarget = target
    case .scrollWheel:
      output.scrollLines += scrollOutput(previous: previousValue, current: next)
    case .steering:
      updateSteering(previous: previousValue, current: next)
      output.virtualAxes[mapping.steeringOutput.axis] = steeringValue
    }
    return output
  }

  mutating func advance(at uptime: UInt64) -> RemappingStickRuntimeOutput {
    let now = max(lastUptime ?? uptime, uptime)
    let elapsed = lastUptime.map { min(now - $0, 100_000_000) } ?? 0
    lastUptime = now
    var output = RemappingStickRuntimeOutput.zero
    if mapping.mode == .aim {
      let scale = Double(elapsed) / 1_000_000_000
        * mapping.aimDegreesPerSecond * mapping.pointerPointsPerDegree
      output.pointerDelta = SIMD2(value.x * scale, -value.y * scale)
    } else if mapping.mode == .steering {
      if value.length < 1, steeringDegrees != 0 {
        let amount = mapping.steeringReturnDegreesPerSecond * Double(elapsed) / 1_000_000_000
          * max(0, 1 - value.length)
        steeringDegrees = Self.approachZero(steeringDegrees, by: amount)
      }
      output.virtualAxes[mapping.steeringOutput.axis] = steeringValue
    } else {
      output.pointerDelta.x = turn.advance(at: now) * mapping.pointerPointsPerDegree
    }
    return output
  }

  private mutating func scrollOutput(
    previous: SIMD2<Double>,
    current: SIMD2<Double>
  ) -> SIMD2<Double> {
    guard current != .zero else {
      previousAngle = nil
      return .zero
    }
    let angle = atan2(current.y, current.x)
    defer { previousAngle = angle }
    guard let oldAngle = previousAngle, previous != .zero else { return .zero }
    let delta = Self.shortestAngle(from: oldAngle, to: angle) * 180 / .pi
      * mapping.rotationDirection.multiplier
    scrollRemainderDegrees += delta
    let lines = (scrollRemainderDegrees / mapping.scrollDegreesPerLine).rounded(.towardZero)
    scrollRemainderDegrees -= lines * mapping.scrollDegreesPerLine
    switch mapping.scrollAxis {
    case .horizontal: return SIMD2(lines, 0)
    case .vertical: return SIMD2(0, lines)
    }
  }

  private mutating func updateSteering(
    previous: SIMD2<Double>,
    current: SIMD2<Double>
  ) {
    guard previous != .zero, current != .zero else { return }
    let oldAngle = atan2(previous.y, previous.x)
    let angle = atan2(current.y, current.x)
    let delta = Self.shortestAngle(from: oldAngle, to: angle) * 180 / .pi
      * current.length * mapping.rotationDirection.multiplier
    steeringDegrees = min(
      mapping.steeringDegreesAtFullScale,
      max(-mapping.steeringDegreesAtFullScale, steeringDegrees + delta)
    )
  }

  private var steeringValue: Double {
    steeringDegrees / mapping.steeringDegreesAtFullScale
  }

  private func neutralizingOutput() -> RemappingStickRuntimeOutput {
    var output = RemappingStickRuntimeOutput.zero
    if mapping.mode == .pointerArea || mapping.mode == .pointerRing {
      output.pointerDelta = -previousTarget
    }
    if mapping.mode == .steering { output.virtualAxes[mapping.steeringOutput.axis] = 0 }
    return output
  }

  private static func shortestAngle(from start: Double, to end: Double) -> Double {
    var delta = (end - start).truncatingRemainder(dividingBy: 2 * .pi)
    if delta > .pi { delta -= 2 * .pi }
    if delta < -.pi { delta += 2 * .pi }
    return delta
  }

  private static func approachZero(_ value: Double, by amount: Double) -> Double {
    guard amount > 0 else { return value }
    if value > 0 { return max(0, value - amount) }
    return min(0, value + amount)
  }
}

private extension SIMD2 where Scalar == Double {
  var length: Double { hypot(x, y) }
}
