import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// Parses a `SOURCE` operand, turning a parser error into a usage error.
func parseSource(_ text: String) throws -> RemappingSource {
  do { return try RemappingCommandValueParser.source(text) } catch {
    throw CLIFailure.usage(
      CLILocalized.format(
        "cli.binding.source_invalid",
        "'%@' is not a source. 'ojd binding set --help' lists the source forms.",
        text
      )
    )
  }
}

/// Parses a `TARGET` operand, turning a parser error into a usage error.
func parseTarget(_ text: String) throws -> RemappingDestination {
  do { return try RemappingCommandValueParser.destination(text) } catch {
    throw CLIFailure.usage(
      CLILocalized.format(
        "cli.binding.target_invalid",
        "'%@' is not a target. 'ojd binding set --help' lists the target forms.",
        text
      )
    )
  }
}

/// The `binding set` options that shape how a binding fires.
struct BindingOptions: ParsableArguments {
  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.option.behavior",
        "When the target fires. Default: the current binding's behavior, or hold."
      )
    )
  )
  var behavior: RemappingBindingBehavior?

  @Option(
    name: .customLong("pulse-ms"),
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.option.pulse_ms",
        "How long a pulse holds the target, 1 to 5000 ms. Default: 100."
      ),
      valueName: "ms"
    )
  )
  var pulseMs: Double?

  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.option.deadzone",
        "Axis sources: the part of the travel that is ignored, 0 to 0.95. Default: 0.1."
      )
    )
  )
  var deadzone: Double?

  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.option.gain",
        "Axis sources: the output scale, 0.1 to 10. Default: 1."
      )
    )
  )
  var gain: Double?

  @Flag(
    help: ArgumentHelp(
      CLILocalized.text("cli.binding.option.invert", "Axis sources: reverse the direction.")
    )
  )
  var invert = false

  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.option.response_curve",
        "Axis sources: how output grows with travel. Default: linear."
      )
    )
  )
  var responseCurve: RemappingResponseCurve?

  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.option.digital_threshold",
        "Axis sources: the travel that counts as a press for button targets. Default: 0.5."
      )
    )
  )
  var digitalThreshold: Double?

  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.option.turbo_rate",
        "Repeat the target this many times a second while held. Needs --turbo-duty."
      ),
      valueName: "hz"
    )
  )
  var turboRate: Double?

  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.option.turbo_duty",
        "The share of each turbo cycle the target is held, above 0 and below 1."
      )
    )
  )
  var turboDuty: Double?

  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.option.long_hold",
        "Send another target when the source is held this long, such as 500:key:b."
      ),
      valueName: "ms:target"
    )
  )
  var longHold: String?

  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.option.double_tap",
        "Send another target when the source is pressed twice within this time, such as "
          + "300:key:c."
      ),
      valueName: "ms:target"
    )
  )
  var doubleTap: String?

  @Option(
    name: .customLong("actions-json"),
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.option.actions_json",
        "Extra actions as a JSON array, in the form 'ojd profile export' writes them."
      ),
      valueName: "json"
    )
  )
  var actionsJSON: String?

  /// The binding for `source` and `target`, keeping the ID, behavior, and actions of `existing`.
  func binding(
    source: RemappingSource,
    target: RemappingDestination,
    existing: RemappingBinding?
  ) throws -> RemappingBinding {
    let behavior = behavior ?? existing?.behavior ?? .hold
    let pulseFallback =
      behavior == .pulse && existing?.behavior == .pulse
      ? existing?.pulseDurationMs ?? RemappingBinding.defaultPulseDurationMs
      : RemappingBinding.defaultPulseDurationMs
    return RemappingBinding(
      id: existing?.id ?? UUID(),
      source: source,
      destination: target,
      behavior: behavior,
      pulseDurationMs: pulseMs ?? pulseFallback,
      axisTuning: try axisTuning(for: source),
      turbo: try turbo(for: target),
      longHold: try alternate(longHold, option: "--long-hold").map {
        RemappingLongHold(durationMs: $0, destination: $1)
      },
      doubleTap: try alternate(doubleTap, option: "--double-tap").map {
        RemappingDoubleTap(windowMs: $0, destination: $1)
      },
      additionalActions: try actions() ?? existing?.additionalActions ?? []
    )
  }

  private func axisTuning(for source: RemappingSource) throws -> RemappingAxisTuning? {
    let isAxis =
      switch source {
      case .axis, .axisDirection: true
      default: false
      }
    guard isAxis else {
      let supplied =
        deadzone != nil || gain != nil || invert || responseCurve != nil || digitalThreshold != nil
      guard !supplied else {
        throw CLIFailure.usage(
          CLILocalized.text(
            "cli.binding.axis_options_source",
            "--deadzone, --gain, --invert, --response-curve, and --digital-threshold need an "
              + "axis source."
          )
        )
      }
      return nil
    }
    return RemappingAxisTuning(
      deadzone: deadzone ?? 0.1,
      gain: gain ?? 1,
      inverted: invert,
      responseCurve: responseCurve ?? .linear,
      digitalActivationThreshold: digitalThreshold ?? 0.5
    )
  }

  private func turbo(for target: RemappingDestination) throws -> RemappingTurbo? {
    guard turboRate != nil || turboDuty != nil else { return nil }
    guard let turboRate, let turboDuty else {
      throw CLIFailure.usage(
        CLILocalized.text(
          "cli.binding.turbo_pair",
          "--turbo-rate and --turbo-duty must be given together."
        )
      )
    }
    guard target.acceptsTurbo else {
      throw CLIFailure.usage(
        CLILocalized.text(
          "cli.binding.turbo_unsupported",
          "Turbo does not work with pointer movement or scrolling targets."
        )
      )
    }
    return RemappingTurbo(repeatRateHz: turboRate, dutyCycle: turboDuty)
  }

  /// Splits `MS:TARGET` once at the first colon.
  private func alternate(_ text: String?, option: String) throws -> (Double, RemappingDestination)?
  {
    guard let text else { return nil }
    let parts = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2, let milliseconds = Double(parts[0]), milliseconds.isFinite else {
      throw CLIFailure.usage(
        CLILocalized.format(
          "cli.binding.alternate_format",
          "%@ takes MS:TARGET, such as 500:key:b.",
          option
        )
      )
    }
    return (milliseconds, try parseTarget(String(parts[1])))
  }

  private func actions() throws -> [RemappingAction]? {
    guard let actionsJSON else { return nil }
    let data = Data(actionsJSON.utf8)
    guard data.count <= RemappingProfile.maximumEncodedBytes else {
      throw CLIFailure.usage(
        CLILocalized.text("cli.binding.actions_too_large", "--actions-json is too large.")
      )
    }
    do { return try JSONDecoder().decode([RemappingAction].self, from: data) } catch {
      throw CLIFailure.usage(
        CLILocalized.format(
          "cli.binding.actions_invalid",
          "--actions-json is not a valid action list: %@",
          DocumentProblem.describe(error)
        )
      )
    }
  }
}
