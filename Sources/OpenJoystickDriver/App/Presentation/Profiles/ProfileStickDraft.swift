import OpenJoystickDriverKit

struct ProfileStickDraft {
  let source: RemappingStickSource
  var enabled: Bool
  var mode: RemappingStickMode
  var innerDeadzone: String
  var outerDeadzone: String
  var responseExponent: String
  var invertX: Bool
  var invertY: Bool
  var aimDegreesPerSecond: String
  var pointerPointsPerDegree: String
  var flickDurationMs: String
  var flickThreshold: String
  var flickHysteresis: String
  var pointerRadiusPoints: String
  var scrollDegreesPerLine: String
  var scrollAxis: RemappingStickScrollAxis
  var rotationDirection: RemappingStickRotationDirection
  var steeringDegreesAtFullScale: String
  var steeringReturnDegreesPerSecond: String
  var steeringOutput: RemappingStickSteeringOutput
  var passthrough: Bool

  init(source: RemappingStickSource, mapping: RemappingStickMapping?) {
    self.source = source
    enabled = mapping != nil
    let value = mapping ?? RemappingStickMapping(source: source)
    mode = value.mode
    innerDeadzone = String(value.tuning.innerDeadzone)
    outerDeadzone = String(value.tuning.outerDeadzone)
    responseExponent = String(value.tuning.responseExponent)
    invertX = value.tuning.invertX
    invertY = value.tuning.invertY
    aimDegreesPerSecond = String(value.aimDegreesPerSecond)
    pointerPointsPerDegree = String(value.pointerPointsPerDegree)
    flickDurationMs = String(value.flickDurationMs)
    flickThreshold = String(value.flickThreshold)
    flickHysteresis = String(value.flickHysteresis)
    pointerRadiusPoints = String(value.pointerRadiusPoints)
    scrollDegreesPerLine = String(value.scrollDegreesPerLine)
    scrollAxis = value.scrollAxis
    rotationDirection = value.rotationDirection
    steeringDegreesAtFullScale = String(value.steeringDegreesAtFullScale)
    steeringReturnDegreesPerSecond = String(value.steeringReturnDegreesPerSecond)
    steeringOutput = value.steeringOutput
    passthrough = value.passthrough
  }

  func validatedMapping(decimalSeparator: String = ".") throws -> RemappingStickMapping? {
    guard enabled else { return nil }
    func number(_ raw: String, _ field: String) throws -> Double {
      guard let value = ProfileMotionDraft.numericValue(raw, decimalSeparator: decimalSeparator)
      else { throw RemappingStickMappingError.invalidField(field) }
      return value
    }
    let mapping = try RemappingStickMapping(
      source: source,
      mode: mode,
      tuning: RemappingStickTuning(
        innerDeadzone: number(innerDeadzone, "inner_deadzone"),
        outerDeadzone: number(outerDeadzone, "outer_deadzone"),
        responseExponent: number(responseExponent, "response_exponent"),
        invertX: invertX,
        invertY: invertY
      ),
      aimDegreesPerSecond: number(aimDegreesPerSecond, "aim_degrees_per_second"),
      pointerPointsPerDegree: number(pointerPointsPerDegree, "pointer_points_per_degree"),
      flickDurationMs: number(flickDurationMs, "flick_duration_ms"),
      flickThreshold: number(flickThreshold, "flick_threshold"),
      flickHysteresis: number(flickHysteresis, "flick_hysteresis"),
      pointerRadiusPoints: number(pointerRadiusPoints, "pointer_radius_points"),
      scrollDegreesPerLine: number(scrollDegreesPerLine, "scroll_degrees_per_line"),
      scrollAxis: scrollAxis,
      rotationDirection: rotationDirection,
      steeringDegreesAtFullScale: number(
        steeringDegreesAtFullScale, "steering_degrees_at_full_scale"
      ),
      steeringReturnDegreesPerSecond: number(
        steeringReturnDegreesPerSecond, "steering_return_degrees_per_second"
      ),
      steeringOutput: steeringOutput,
      passthrough: passthrough
    )
    try mapping.validate()
    return mapping
  }
}
