import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// Parses a `SOURCE` operand, turning a parser error into a usage error.
///
/// - Throws: ``CLIFailure`` with the usage code when `text` is not a source.
func parseSource(_ text: String) throws -> RemappingSource {
  do { return try RemappingCommandValueParser.source(text) } catch {
    throw CLIFailure.usage(
      CLILocalized.format(
        "cli.binding.group.sourceInvalid",
        text
      )
    )
  }
}

/// Parses a `TARGET` operand, turning a parser error into a usage error.
///
/// - Throws: ``CLIFailure`` with the usage code when `text` is not a target.
func parseTarget(_ text: String) throws -> RemappingDestination {
  do { return try RemappingCommandValueParser.destination(text) } catch {
    throw CLIFailure.usage(
      CLILocalized.format(
        "cli.binding.group.targetInvalid",
        text
      )
    )
  }
}

/// The `binding set` options that shape how a binding fires.
struct BindingOptions: ParsableArguments {
  /// `--behavior`: when the target fires.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.group.optionBehavior"
      )
    )
  )
  var behavior: RemappingBindingBehavior?

  /// `--pulse-ms`: how long `pulse` holds the target, in milliseconds.
  @Option(
    name: .customLong("pulse-ms"),
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.group.optionPulseMs"
      ),
      valueName: "ms"
    )
  )
  var pulseMs: Double?

  /// `--deadzone`: the dead zone of an axis source.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.group.optionDeadzone"
      )
    )
  )
  var deadzone: Double?

  /// `--gain`: the gain of an axis source.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.group.optionGain"
      )
    )
  )
  var gain: Double?

  /// `--invert`: invert an axis source.
  @Flag(
    help: ArgumentHelp(
      CLILocalized.text("cli.binding.group.optionInvert")
    )
  )
  var invert = false

  /// `--response-curve`: the response curve of an axis source.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.group.optionResponseCurve"
      )
    )
  )
  var responseCurve: RemappingResponseCurve?

  /// `--digital-threshold`: the travel of an axis source that counts as a press.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.group.optionDigitalThreshold"
      )
    )
  )
  var digitalThreshold: Double?

  /// `--turbo-rate`: how many times a second the target repeats while the source is held; it needs
  /// `--turbo-duty`.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.group.optionTurboRate"
      ),
      valueName: "hz"
    )
  )
  var turboRate: Double?

  /// `--turbo-duty`: the part of each turbo cycle that the target is held; it needs `--turbo-rate`.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.group.optionTurboDuty"
      )
    )
  )
  var turboDuty: Double?

  /// `--turbo-delay`: the time from the first press to the first repeat, in milliseconds; it needs
  /// `--turbo-rate` and `--turbo-duty`.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.group.optionTurboDelay"
      ),
      valueName: "ms"
    )
  )
  var turboDelay: Double?

  /// `--turbo-max`: how many repeats follow the first press; it needs `--turbo-rate` and
  /// `--turbo-duty`.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.group.optionTurboMax"
      ),
      valueName: "count"
    )
  )
  var turboMax: Int?

  /// `--voice`: the voice identifier of a `speak:TEXT` target.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text("cli.binding.group.optionVoice"),
      valueName: "identifier"
    )
  )
  var voice: String?

  /// The destination of a `TARGET` operand: `speak:TEXT` with `--voice`, else ``parseTarget(_:)``.
  ///
  /// - Throws: ``CLIFailure`` with the usage code when `--voice` goes with another target or
  ///   `text` is not a target.
  func destination(_ text: String) throws -> RemappingDestination {
    let prefix = "speak:"
    guard text.hasPrefix(prefix) else {
      guard voice == nil else {
        throw CLIFailure.usage(CLILocalized.text("cli.binding.group.voiceNeedsSpeak"))
      }
      return try parseTarget(text)
    }
    return .speak(text: String(text.dropFirst(prefix.count)), voice: voice)
  }

  /// `--long-hold`: a `MS:TARGET` to send when the source is held for that long.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.group.optionLongHold"
      ),
      valueName: "ms:target"
    )
  )
  var longHold: String?

  /// `--multi-tap`: a `COUNT:MS:TARGET` to send when the source is tapped that many times, each
  /// press within that time of the last release; it can repeat.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.group.optionMultiTap"
      ),
      valueName: "count:ms:target"
    )
  )
  var multiTap: [String] = []

  /// `--actions-json`: more actions, as a JSON array in the form that `ojd profile export` writes.
  @Option(
    name: .customLong("actions-json"),
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.group.optionActionsJson"
      ),
      valueName: "json"
    )
  )
  var actionsJSON: String?

  /// The binding for `source` and `target`, keeping the ID, behavior, and actions of `existing`.
  ///
  /// - Throws: ``CLIFailure`` with the usage code when axis options are given for a source that is
  ///   not an axis, turbo options are incomplete or not usable with the target, `--long-hold` or
  ///   `--multi-tap` is not `COUNT:MS:TARGET`, or `--actions-json` is too large or not valid.
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
      multiTap: try multiTap.map(multiTapEntry),
      additionalActions: try actions() ?? existing?.additionalActions ?? []
    )
  }

  /// The axis tuning of the options for an axis `source`, or nil for another source.
  ///
  /// - Throws: ``CLIFailure`` with the usage code when an axis option is given for a source that is
  ///   not an axis.
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
            "cli.binding.group.axisOptionsSource"
          )
        )
      }
      return nil
    }
    return RemappingAxisTuning(
      deadzone: deadzone ?? RemappingAxisTuning.defaultDeadzone,
      gain: gain ?? RemappingAxisTuning.defaultGain,
      inverted: invert,
      responseCurve: responseCurve ?? .linear,
      digitalActivationThreshold: digitalThreshold
        ?? RemappingAxisTuning.defaultDigitalActivationThreshold
    )
  }

  /// The turbo setting of the options, or nil when neither turbo option is given.
  ///
  /// - Throws: ``CLIFailure`` with the usage code when only one turbo option is given or `target`
  ///   cannot repeat.
  private func turbo(for target: RemappingDestination) throws -> RemappingTurbo? {
    guard turboRate != nil || turboDuty != nil || turboDelay != nil || turboMax != nil else {
      return nil
    }
    guard let turboRate, let turboDuty else {
      throw CLIFailure.usage(
        CLILocalized.text(
          "cli.binding.group.turboPair"
        )
      )
    }
    guard target.acceptsTurbo else {
      throw CLIFailure.usage(
        CLILocalized.text(
          "cli.binding.group.turboUnsupported"
        )
      )
    }
    return RemappingTurbo(
      repeatRateHz: turboRate,
      dutyCycle: turboDuty,
      initialDelayMs: turboDelay ?? 0,
      maxRepeats: turboMax
    )
  }

  /// Splits `MS:TARGET` once at the first colon.
  ///
  /// - Parameters:
  ///   - text: The value to split; nil when the option is absent.
  ///   - option: The option name that an error message names.
  /// - Returns: The milliseconds and the target, or nil when `text` is nil.
  /// - Throws: ``CLIFailure`` with a usage error that names `option` when the value is not a finite
  ///   number of milliseconds, a colon and a target.
  private func alternate(_ text: String?, option: String) throws -> (Double, RemappingDestination)?
  {
    guard let text else { return nil }
    let parts = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2, let milliseconds = Double(parts[0]), milliseconds.isFinite else {
      throw CLIFailure.usage(
        CLILocalized.format(
          "cli.binding.group.alternateFormat",
          option
        )
      )
    }
    return (milliseconds, try parseTarget(String(parts[1])))
  }

  /// Parses one `COUNT:MS:TARGET` value of `--multi-tap`.
  ///
  /// - Throws: ``CLIFailure`` with a usage error when the value is not a count, a finite number of
  ///   milliseconds, and a target.
  private func multiTapEntry(_ text: String) throws -> RemappingMultiTap {
    let parts = text.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
    guard parts.count == 3, let count = Int(parts[0]), let milliseconds = Double(parts[1]),
      milliseconds.isFinite
    else { throw CLIFailure.usage(CLILocalized.text("cli.binding.group.multiTapFormat")) }
    return RemappingMultiTap(
      count: count,
      windowMs: milliseconds,
      destination: try parseTarget(String(parts[2]))
    )
  }

  /// The actions that `--actions-json` holds, or nil when it is not given.
  private func actions() throws -> [RemappingAction]? {
    guard let actionsJSON else { return nil }
    let data = Data(actionsJSON.utf8)
    guard data.count <= RemappingProfile.maximumEncodedBytes else {
      throw CLIFailure.usage(
        CLILocalized.text("cli.binding.group.actionsTooLarge")
      )
    }
    do { return try JSONDecoder().decode([RemappingAction].self, from: data) } catch {
      throw CLIFailure.usage(
        CLILocalized.format(
          "cli.binding.group.actionsInvalid",
          DocumentProblem.describe(error)
        )
      )
    }
  }
}
