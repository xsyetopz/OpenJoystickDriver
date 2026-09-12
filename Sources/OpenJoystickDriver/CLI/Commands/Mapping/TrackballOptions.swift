import OpenJoystickDriverKit

extension MappingProfileEditor {
  static func trackball(
    _ options: MappingOptions, defaultValue: RemappingGyroTrackball?
  ) throws -> RemappingGyroTrackball? {
    let rawSource = options["--gyro-trackball-source"]
    let hasTuning = options["--gyro-trackball-axes"] != nil
      || options["--gyro-trackball-decay"] != nil || options["--gyro-trackball-consume"] != nil
    if rawSource == "none" {
      guard !hasTuning else {
        throw MappingCommandError.invalidArguments("Trackball removal cannot include tuning")
      }
      return nil
    }
    let source = try rawSource.map(MappingSyntax.source) ?? defaultValue?.source
    guard let source else {
      guard !hasTuning else {
        throw MappingCommandError.invalidArguments("--gyro-trackball-source is required")
      }
      return nil
    }
    let rawAxes = options["--gyro-trackball-axes"] ?? defaultValue?.axes.rawValue ?? "both"
    guard let axes = RemappingGyroTrackballAxes(rawValue: rawAxes) else {
      throw MappingCommandError.invalidArguments("--gyro-trackball-axes: pitch|yaw|both")
    }
    let rawConsumption = options["--gyro-trackball-consume"]
      ?? String(defaultValue?.consumesSource ?? true)
    guard rawConsumption == "true" || rawConsumption == "false" else {
      throw MappingCommandError.invalidArguments("--gyro-trackball-consume: true|false")
    }
    let decay: Double
    if let raw = options["--gyro-trackball-decay"] {
      decay = try MappingSyntax.finiteDouble(raw, option: "--gyro-trackball-decay")
    } else { decay = defaultValue?.decayHalvingsPerSecond ?? 1 }
    let result = RemappingGyroTrackball(
      source: source,
      axes: axes,
      decayHalvingsPerSecond: decay,
      consumesSource: rawConsumption == "true"
    )
    try result.validate()
    return result
  }
}
