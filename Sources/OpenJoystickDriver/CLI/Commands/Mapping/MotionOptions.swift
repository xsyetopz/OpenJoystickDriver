import OpenJoystickDriverKit

extension MappingProfileEditor {
  static let motionOptions: Set<String> = [
    "--motion-space",
    "--motion-pitch-sensitivity",
    "--motion-yaw-sensitivity",
    "--motion-smoothing-half-time-ms",
    "--motion-threshold-degrees-per-second",
    "--motion-yaw-relaxation",
    "--motion-side-reduction-threshold",
    "--motion-gravity-correction-rate",
    "--motion-invert-pitch",
    "--motion-invert-yaw",
    "--motion-automatic-bias",
    "--motion-lean",
    "--motion-lean-threshold-degrees",
    "--motion-lean-hysteresis-degrees",
    "--motion-steering-output",
    "--motion-steering-deadzone-degrees",
    "--motion-steering-full-scale-degrees",
    "--motion-steering-response-exponent",
    "--motion-steering-inverted",
    "--gyro-output",
    "--gyro-trackball-source",
    "--gyro-trackball-axes",
    "--gyro-trackball-decay",
    "--gyro-trackball-consume",
    "--gyro-activation",
    "--gyro-activation-source",
    "--gyro-consume-activation",
    "--gyro-pointer-points-per-degree",
    "--gyro-full-stick-degrees-per-second"
  ]

  static func motionTuning(
    _ options: MappingOptions, defaultValue: RemappingMotionTuning = .default
  ) throws -> RemappingMotionTuning {
    let rawSpace = options["--motion-space"] ?? defaultValue.space.rawValue
    guard let space = RemappingMotionSpace(rawValue: rawSpace) else {
      throw MappingCommandError.invalidArguments("--motion-space: local|player|world")
    }
    func number(_ option: String, _ fallback: Double) throws -> Double {
      guard let raw = options[option] else { return fallback }
      guard let value = Double(raw), value.isFinite else {
        throw MappingCommandError.invalidArguments(option + ": finite number required")
      }
      return value
    }
    func boolean(_ option: String, _ fallback: Bool) throws -> Bool {
      guard let raw = options[option] else { return fallback }
      guard raw == "true" || raw == "false" else {
        throw MappingCommandError.invalidArguments(option + ": true|false")
      }
      return raw == "true"
    }
    let lean: RemappingMotionLean?
    let hasLeanOptions = options.contains("--motion-lean")
      || options.contains("--motion-lean-threshold-degrees")
      || options.contains("--motion-lean-hysteresis-degrees")
    if hasLeanOptions {
      let enabled = try boolean("--motion-lean", defaultValue.lean != nil)
      if enabled {
        let old = defaultValue.lean ?? RemappingMotionLean()
        lean = try RemappingMotionLean(
          thresholdDegrees: number(
            "--motion-lean-threshold-degrees", old.thresholdDegrees
          ),
          hysteresisDegrees: number(
            "--motion-lean-hysteresis-degrees", old.hysteresisDegrees
          )
        )
      } else {
        guard !options.contains("--motion-lean-threshold-degrees"),
          !options.contains("--motion-lean-hysteresis-degrees")
        else { throw MappingCommandError.invalidArguments("Cannot tune disabled motion lean") }
        lean = nil
      }
    } else {
      lean = defaultValue.lean
    }
    let steering: RemappingMotionSteering?
    let steeringOptions = [
      "--motion-steering-output", "--motion-steering-deadzone-degrees",
      "--motion-steering-full-scale-degrees", "--motion-steering-response-exponent",
      "--motion-steering-inverted",
    ]
    if steeringOptions.contains(where: options.contains) {
      let rawOutput = options["--motion-steering-output"]
        ?? defaultValue.steering?.output.rawValue ?? "left_stick_x"
      if rawOutput == "none" {
        guard !steeringOptions.dropFirst().contains(where: options.contains) else {
          throw MappingCommandError.invalidArguments("Cannot tune disabled motion steering")
        }
        steering = nil
      } else {
        guard let output = RemappingMotionSteeringOutput(rawValue: rawOutput) else {
          throw MappingCommandError.invalidArguments(
            "--motion-steering-output: left_stick_x|right_stick_x|none"
          )
        }
        let old = defaultValue.steering ?? RemappingMotionSteering()
        steering = try RemappingMotionSteering(
          output: output,
          deadzoneDegrees: number(
            "--motion-steering-deadzone-degrees", old.deadzoneDegrees
          ),
          fullScaleDegrees: number(
            "--motion-steering-full-scale-degrees", old.fullScaleDegrees
          ),
          responseExponent: number(
            "--motion-steering-response-exponent", old.responseExponent
          ),
          inverted: boolean("--motion-steering-inverted", old.inverted)
        )
      }
    } else {
      steering = defaultValue.steering
    }
    let tuning = try RemappingMotionTuning(
      space: space,
      pitchSensitivity: number(
        "--motion-pitch-sensitivity", defaultValue.pitchSensitivity
      ),
      yawSensitivity: number(
        "--motion-yaw-sensitivity", defaultValue.yawSensitivity
      ),
      invertPitch: boolean(
        "--motion-invert-pitch", defaultValue.invertPitch
      ),
      invertYaw: boolean(
        "--motion-invert-yaw", defaultValue.invertYaw
      ),
      smoothingHalfTimeMs: number(
        "--motion-smoothing-half-time-ms", defaultValue.smoothingHalfTimeMs
      ),
      thresholdDegreesPerSecond: number(
        "--motion-threshold-degrees-per-second", defaultValue.thresholdDegreesPerSecond
      ),
      automaticBias: boolean(
        "--motion-automatic-bias", defaultValue.automaticBias
      ),
      yawRelaxation: number(
        "--motion-yaw-relaxation", defaultValue.yawRelaxation
      ),
      sideReductionThreshold: number(
        "--motion-side-reduction-threshold", defaultValue.sideReductionThreshold
      ),
      gravityCorrectionRate: number(
        "--motion-gravity-correction-rate", defaultValue.gravityCorrectionRate
      ),
      lean: lean,
      steering: steering
    )
    try tuning.validate()
    return tuning
  }
}
