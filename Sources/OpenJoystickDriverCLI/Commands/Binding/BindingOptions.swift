import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// Parses a `SOURCE` operand, turning a parser error into a usage error.
func parseSource(_ text: String) throws -> RemappingSource {
  do { return try RemappingCommandValueParser.source(text) } catch {
    throw CLIFailure.usage(
      CLILocalized.format(
        "cli.binding.source_invalid",
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
        "cli.binding.option.behavior"
      )
    )
  )
  var behavior: RemappingBindingBehavior?

  @Option(
    name: .customLong("pulse-ms"),
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.option.pulse_ms"
      ),
      valueName: "ms"
    )
  )
  var pulseMs: Double?

  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.option.deadzone"
      )
    )
  )
  var deadzone: Double?

  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.option.gain"
      )
    )
  )
  var gain: Double?

  @Flag(
    help: ArgumentHelp(
      CLILocalized.text("cli.binding.option.invert")
    )
  )
  var invert = false

  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.option.response_curve"
      )
    )
  )
  var responseCurve: RemappingResponseCurve?

  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.option.digital_threshold"
      )
    )
  )
  var digitalThreshold: Double?

  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.option.turbo_rate"
      ),
      valueName: "hz"
    )
  )
  var turboRate: Double?

  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.option.turbo_duty"
      )
    )
  )
  var turboDuty: Double?

  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.option.long_hold"
      ),
      valueName: "ms:target"
    )
  )
  var longHold: String?

  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.option.double_tap"
      ),
      valueName: "ms:target"
    )
  )
  var doubleTap: String?

  @Option(
    name: .customLong("actions-json"),
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.option.actions_json"
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
            "cli.binding.axis_options_source"
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
          "cli.binding.turbo_pair"
        )
      )
    }
    guard target.acceptsTurbo else {
      throw CLIFailure.usage(
        CLILocalized.text(
          "cli.binding.turbo_unsupported"
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
        CLILocalized.text("cli.binding.actions_too_large")
      )
    }
    do { return try JSONDecoder().decode([RemappingAction].self, from: data) } catch {
      throw CLIFailure.usage(
        CLILocalized.format(
          "cli.binding.actions_invalid",
          DocumentProblem.describe(error)
        )
      )
    }
  }
}
