import OpenJoystickDriverKit

extension MappingProfileEditor {
  static func gyroOutput(
    _ options: MappingOptions,
    defaultValue: RemappingGyroOutput = .default
  ) throws -> RemappingGyroOutput {
    let rawMode = options["--gyro-output"] ?? defaultValue.mode.rawValue
    guard let mode = RemappingGyroOutputMode(rawValue: rawMode) else {
      throw MappingCommandError.invalidArguments(
        "--gyro-output: disabled|mouse|left_stick|right_stick"
      )
    }
    func number(_ option: String, fallback: Double) throws -> Double {
      guard let raw = options[option] else { return fallback }
      return try MappingSyntax.finiteDouble(raw, option: option)
    }
    let rawActivation = options["--gyro-activation"] ?? defaultValue.activationMode.rawValue
    guard let activation = RemappingGyroActivationMode(rawValue: rawActivation) else {
      throw MappingCommandError.invalidArguments(
        "--gyro-activation: always|while_held|while_released|toggle"
      )
    }
    let source: RemappingSource?
    if let rawSource = options["--gyro-activation-source"] {
      source = try MappingSyntax.source(rawSource)
    } else {
      source = activation == .always ? nil : defaultValue.activationSource
    }
    let rawConsumption =
      options["--gyro-consume-activation"] ?? String(defaultValue.consumesActivationSource)
    guard rawConsumption == "true" || rawConsumption == "false" else {
      throw MappingCommandError.invalidArguments("--gyro-consume-activation: true|false")
    }
    let rawVirtualMotion = options["--gyro-virtual-motion"] ?? String(defaultValue.virtualMotion)
    guard rawVirtualMotion == "true" || rawVirtualMotion == "false" else {
      throw MappingCommandError.invalidArguments("--gyro-virtual-motion: true|false")
    }
    let output = try RemappingGyroOutput(
      mode: mode,
      pointerPointsPerDegree: number(
        "--gyro-pointer-points-per-degree",
        fallback: defaultValue.pointerPointsPerDegree
      ),
      fullStickDegreesPerSecond: number(
        "--gyro-full-stick-degrees-per-second",
        fallback: defaultValue.fullStickDegreesPerSecond
      ),
      activationMode: activation,
      activationSource: source,
      consumesActivationSource: rawConsumption == "true",
      trackball: trackball(options, defaultValue: defaultValue.trackball),
      virtualMotion: rawVirtualMotion == "true"
    )
    try output.validate()
    return output
  }
}
