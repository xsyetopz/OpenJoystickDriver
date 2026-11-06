import OpenJoystickDriverKit

/// One stick mapping as the stick sheet edits it, with the numbers as text.
struct ProfileStickDraft {
  /// The stick.
  let source: RemappingStickSource
  /// Whether the stick has a mapping.
  var enabled: Bool
  /// The mode of the mapping.
  var mode: RemappingStickMode
  /// The inner dead zone.
  var innerDeadzone: String
  /// The outer dead zone.
  var outerDeadzone: String
  /// The response exponent.
  var responseExponent: String
  /// Whether the X axis is inverted.
  var invertX: Bool
  /// Whether the Y axis is inverted.
  var invertY: Bool
  /// The aim rate in degrees per second.
  var aimDegreesPerSecond: String
  /// The pointer points per degree.
  var pointerPointsPerDegree: String
  /// The flick duration in milliseconds.
  var flickDurationMs: String
  /// The flick threshold.
  var flickThreshold: String
  /// The flick hysteresis.
  var flickHysteresis: String
  /// The pointer radius in points.
  var pointerRadiusPoints: String
  /// The degrees per scrolled line.
  var scrollDegreesPerLine: String
  /// The scroll axis.
  var scrollAxis: RemappingStickScrollAxis
  /// The rotation direction.
  var rotationDirection: RemappingStickRotationDirection
  /// The steering degrees at full scale.
  var steeringDegreesAtFullScale: String
  /// The steering return rate in degrees per second.
  var steeringReturnDegreesPerSecond: String
  /// The stick that steering moves.
  var steeringOutput: RemappingStickSteeringOutput
  /// Whether the stick keeps acting as itself.
  var passthrough: Bool

  /// Creates the draft of `source` from its mapping, or the defaults when it has none.
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

  /// Returns the mapping that the draft describes, or nil when the stick has none.
  ///
  /// - Parameter decimalSeparator: The separator the person types in the numbers.
  /// - Returns: The mapping that the draft describes, or nil when the stick has none.
  /// - Throws: ``RemappingStickMappingError`` when a number cannot be read, and the error of the
  ///   mapping's validation when its values are out of range.
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
        steeringDegreesAtFullScale,
        "steering_degrees_at_full_scale"
      ),
      steeringReturnDegreesPerSecond: number(
        steeringReturnDegreesPerSecond,
        "steering_return_degrees_per_second"
      ),
      steeringOutput: steeringOutput,
      passthrough: passthrough
    )
    try mapping.validate()
    return mapping
  }
}
