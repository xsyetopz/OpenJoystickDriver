import OpenJoystickDriverKit

extension MappingProfileEditor {
  static let stickOptions: Set<String> = [
    "--stick-source", "--stick-mode", "--stick-inner-deadzone", "--stick-outer-deadzone",
    "--stick-response-exponent", "--stick-invert-x", "--stick-invert-y",
    "--stick-aim-degrees-per-second", "--stick-pointer-points-per-degree",
    "--stick-flick-duration-ms", "--stick-flick-threshold", "--stick-flick-hysteresis",
    "--stick-pointer-radius-points", "--stick-scroll-degrees-per-line", "--stick-scroll-axis",
    "--stick-rotation-direction", "--stick-steering-degrees-at-full-scale",
    "--stick-steering-return-degrees-per-second", "--stick-steering-output",
    "--stick-passthrough"
  ]

  static func stickMappings(
    _ options: MappingOptions, defaultValue: [RemappingStickMapping] = []
  ) throws -> [RemappingStickMapping] {
    guard stickOptions.contains(where: options.contains) else { return defaultValue }
    guard let rawSource = options["--stick-source"],
      let source = RemappingStickSource(rawValue: rawSource)
    else { throw MappingCommandError.invalidArguments("--stick-source: left|right required") }
    let old = defaultValue.first { $0.source == source } ?? RemappingStickMapping(source: source)
    let rawMode = options["--stick-mode"] ?? old.mode.rawValue
    if rawMode == "none" {
      guard !stickOptions.subtracting(["--stick-source", "--stick-mode"])
        .contains(where: options.contains)
      else { throw MappingCommandError.invalidArguments("Cannot tune a removed stick mapping") }
      return defaultValue.filter { $0.source != source }
    }
    guard let mode = RemappingStickMode(rawValue: rawMode) else {
      throw MappingCommandError.invalidArguments(
        "--stick-mode: aim|flick|flick_only|rotate_only|pointer_area|pointer_ring|"
          + "scroll_wheel|steering|none"
      )
    }
    func number(_ suffix: String, _ fallback: Double) throws -> Double {
      let key = "--stick-" + suffix
      guard let raw = options[key] else { return fallback }
      return try MappingSyntax.finiteDouble(raw, option: key)
    }
    func boolean(_ suffix: String, _ fallback: Bool) throws -> Bool {
      let key = "--stick-" + suffix
      guard let raw = options[key] else { return fallback }
      guard raw == "true" || raw == "false" else {
        throw MappingCommandError.invalidArguments(key + ": true|false")
      }
      return raw == "true"
    }
    func choice<Value: RawRepresentable>(
      _ suffix: String,
      _ fallback: Value,
      as _: Value.Type
    ) throws -> Value where Value.RawValue == String {
      let key = "--stick-" + suffix
      guard let raw = options[key] else { return fallback }
      guard let value = Value(rawValue: raw) else {
        throw MappingCommandError.invalidArguments(key + ": invalid value")
      }
      return value
    }
    let mapping = try RemappingStickMapping(
      source: source,
      mode: mode,
      tuning: RemappingStickTuning(
        innerDeadzone: number("inner-deadzone", old.tuning.innerDeadzone),
        outerDeadzone: number("outer-deadzone", old.tuning.outerDeadzone),
        responseExponent: number("response-exponent", old.tuning.responseExponent),
        invertX: boolean("invert-x", old.tuning.invertX),
        invertY: boolean("invert-y", old.tuning.invertY)
      ),
      aimDegreesPerSecond: number("aim-degrees-per-second", old.aimDegreesPerSecond),
      pointerPointsPerDegree: number("pointer-points-per-degree", old.pointerPointsPerDegree),
      flickDurationMs: number("flick-duration-ms", old.flickDurationMs),
      flickThreshold: number("flick-threshold", old.flickThreshold),
      flickHysteresis: number("flick-hysteresis", old.flickHysteresis),
      pointerRadiusPoints: number("pointer-radius-points", old.pointerRadiusPoints),
      scrollDegreesPerLine: number("scroll-degrees-per-line", old.scrollDegreesPerLine),
      scrollAxis: choice("scroll-axis", old.scrollAxis, as: RemappingStickScrollAxis.self),
      rotationDirection: choice(
        "rotation-direction", old.rotationDirection, as: RemappingStickRotationDirection.self
      ),
      steeringDegreesAtFullScale: number(
        "steering-degrees-at-full-scale", old.steeringDegreesAtFullScale
      ),
      steeringReturnDegreesPerSecond: number(
        "steering-return-degrees-per-second", old.steeringReturnDegreesPerSecond
      ),
      steeringOutput: choice(
        "steering-output", old.steeringOutput, as: RemappingStickSteeringOutput.self
      ),
      passthrough: boolean("passthrough", old.passthrough)
    )
    try mapping.validate()
    var mappings = defaultValue
    if let index = mappings.firstIndex(where: { $0.source == source }) {
      mappings[index] = mapping
    } else {
      mappings.append(mapping)
    }
    return mappings
  }
}
