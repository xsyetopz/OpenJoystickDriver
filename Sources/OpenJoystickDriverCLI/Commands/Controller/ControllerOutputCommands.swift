import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `--json` result of `ojd controller rumble`, `light`, and `player`: the `details` of a
/// `Success` status.
///
/// A result the controller does not deliver fails the command instead.
struct ControllerOutputReport: Encodable, Equatable {
  /// One output command and what happened to it.
  struct Entry: Encodable, Equatable {
    /// The output command that the service received.
    let command: String
    /// How the controller took the command.
    let outcome: String
    /// The rumble channels that the controller dropped because it lacks them.
    let droppedRumbleChannels: [String]
  }

  /// The session ID of the controller.
  let controller: String
  /// One entry for each output command sent.
  let results: [Entry]
}

/// One output command and the words that name it in a failure.
private struct OutputRequest: Sendable {
  /// The name of the command in a failure message.
  let name: String
  /// The command to send.
  let command: ControllerOutputCommand
  /// The feature in a failure message, such as rumble.
  let feature: String
}

/// Sends each request to the selected controller in order and prints the report.
///
/// Fails at the first request the controller does not deliver.
private func sendOutput(_ requests: [OutputRequest], to selector: ControllerSelector) async throws {
  let entries = try await ServiceConnection.request { client in
    let device = try await selector.resolve(with: client)
    var entries: [ControllerOutputReport.Entry] = []
    for request in requests {
      let result = try await client.sendControllerOutput(
        request.command,
        for: .session(device.sessionToken)
      )
      try check(result, request, device)
      entries.append(
        ControllerOutputReport.Entry(
          command: request.name,
          outcome: result.outcome.rawValue,
          droppedRumbleChannels: result.droppedRumbleChannels.map(\.rawValue)
        )
      )
    }
    return (device, entries)
  }
  let report = ControllerOutputReport(
    controller: entries.0.sessionToken.rawValue,
    results: entries.1
  )
  switch CLIContext.current.format {
  case .json: try CLIOutput.json(CLIStatus(details: report))
  case .plain:
    CLIOutput.plain(
      report.results.map {
        [$0.command, $0.outcome, $0.droppedRumbleChannels.joined(separator: ",")]
      }
    )
  case .human:
    CLIOutput.success(
      CLILocalized.format(
        "cli.controller.group.outputSent",
        report.results.map(\.command).joined(separator: ", "),
        entries.0.name
      )
    )
  }
}

/// Fails with ``CLIFailure`` when `result` shows that the controller did not deliver `request`.
private func check(
  _ result: ControllerOutputResult,
  _ request: OutputRequest,
  _ device: ApplicationServiceDeviceDescription
) throws {
  switch result.outcome {
  case .delivered: return
  case .unsupportedCapability:
    throw CLIFailure(
      .controllerRequestFailed,
      CLILocalized.format(
        "cli.controller.group.outputUnsupported",
        device.name,
        request.feature,
        device.sessionToken.rawValue
      )
    )
  case .notReady:
    throw CLIFailure(
      .controllerRequestFailed,
      CLILocalized.format(
        "cli.controller.group.outputNotReady",
        device.name
      )
    )
  case .notFound, .cancelled:
    throw CLIFailure(
      .controllerRequestFailed,
      CLILocalized.format(
        "cli.controller.group.outputGone",
        device.name
      )
    )
  case .invalidValue, .writeFailed:
    throw CLIFailure(
      .controllerRequestFailed,
      CLILocalized.format(
        "cli.controller.group.outputFailed",
        device.name,
        request.name,
        CommandLineName.kebab(result.outcome.rawValue)
      )
    )
  }
}

/// The `ojd controller rumble` command: runs the rumble motors of a controller for a short time.
struct ControllerRumbleCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "rumble",
    abstract: CLILocalized.text(
      "cli.controller.rumble.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.controller.rumble.discussion"
    ) + "\n\n" + CLILocalized.text("cli.controller.rumble.examples")
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// The controller to rumble.
  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  /// `--left`: the intensity of the left main motor, from 0 to 255.
  @Option(help: intensityHelp(CLILocalized.text("cli.controller.rumble.left")))
  var left: UInt8?

  /// `--right`: the intensity of the right main motor, from 0 to 255.
  @Option(help: intensityHelp(CLILocalized.text("cli.controller.rumble.right")))
  var right: UInt8?

  /// `--left-trigger`: the intensity of the left trigger motor, from 0 to 255.
  @Option(
    help: intensityHelp(CLILocalized.text("cli.controller.rumble.leftTrigger"))
  )
  var leftTrigger: UInt8?

  /// `--right-trigger`: the intensity of the right trigger motor, from 0 to 255.
  @Option(
    help: intensityHelp(CLILocalized.text("cli.controller.rumble.rightTrigger"))
  )
  var rightTrigger: UInt8?

  /// `--duration`: how long the motors run, in seconds above 0 and up to the maximum.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.controller.rumble.duration"
      ),
      valueName: "seconds"
    )
  )
  var duration = RumbleDuration.manualTestSeconds

  /// The help of an intensity option, which takes a value from 0 to 255.
  private static func intensityHelp(_ text: String) -> ArgumentHelp {
    ArgumentHelp(text, valueName: "0-255")
  }

  /// Checks the rumble options, including that the duration is above zero and within the maximum.
  ///
  /// - Throws: ``ValidationError`` for an invalid duration.
  func validate() throws {
    guard duration.isFinite, duration > 0, duration <= RumbleDuration.maximumSeconds else {
      throw ValidationError(
        CLILocalized.text(
          "cli.controller.rumble.errorDuration"
        )
      )
    }
  }

  /// The requested intensities; both main motors at 180 when no option names one.
  var intensities: RumbleIntensities {
    .manualTest(
      lowFrequency: left,
      highFrequency: right,
      leftTrigger: leftTrigger,
      rightTrigger: rightTrigger
    )
  }

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let intensities = intensities
      let command: ControllerOutputCommand =
        intensities.activeMotors.isEmpty
        ? .stopRumble
        : .setRumble(
          intensities.mirroringMainOntoHaptics(),
          duration: .milliseconds(max(1, Int((duration * 1000).rounded())))
        )
      let selector = controller
      let feature = CLILocalized.text("cli.controller.group.featureRumble")
      try await sendRumble(
        OutputRequest(name: "rumble", command: command, feature: feature),
        requested: intensities.activeMotors,
        to: selector
      )
    }
  }

  /// Sends the rumble and warns about each requested trigger motor the controller lacks.
  ///
  /// Main-motor requests are mirrored onto trackpad haptics, so a controller with only one of
  /// the two drops the other silently. Fails when no requested motor ran.
  private func sendRumble(
    _ request: OutputRequest,
    requested: [PhysicalRumbleMotor],
    to selector: ControllerSelector
  ) async throws {
    let (device, result) = try await ServiceConnection.request { client in
      let device = try await selector.resolve(with: client)
      let result = try await client.sendControllerOutput(
        request.command,
        for: .session(device.sessionToken)
      )
      return (device, result)
    }
    try check(result, request, device)
    let dropped = Set(result.droppedRumbleChannels)
    let droppedTriggers = requested.filter {
      ($0 == .leftTrigger || $0 == .rightTrigger) && dropped.contains($0)
    }
    let ran = requested.filter { motor in
      switch motor {
      case .lowFrequency: !dropped.contains(.lowFrequency) || !dropped.contains(.leftHaptic)
      case .highFrequency: !dropped.contains(.highFrequency) || !dropped.contains(.rightHaptic)
      default: !dropped.contains(motor)
      }
    }
    for motor in droppedTriggers {
      CLIOutput.stderr(
        CLILocalized.format(
          "cli.controller.rumble.dropped",
          device.name,
          CommandLineName.kebab(motor.rawValue)
        )
      )
    }
    if !requested.isEmpty, ran.isEmpty {
      throw CLIFailure(
        .controllerRequestFailed,
        CLILocalized.format(
          "cli.controller.rumble.noneRan",
          device.name,
          device.sessionToken.rawValue
        )
      )
    }
    let report = ControllerOutputReport(
      controller: device.sessionToken.rawValue,
      results: [
        ControllerOutputReport.Entry(
          command: request.name,
          outcome: result.outcome.rawValue,
          droppedRumbleChannels: result.droppedRumbleChannels.map(\.rawValue)
        )
      ]
    )
    switch CLIContext.current.format {
    case .json: try CLIOutput.json(CLIStatus(details: report))
    case .plain:
      CLIOutput.plain([
        [
          request.name, CommandLineName.kebab(result.outcome.rawValue),
          droppedTriggers.map { CommandLineName.kebab($0.rawValue) }.joined(separator: ","),
        ]
      ])
    case .human:
      CLIOutput.success(
        requested.isEmpty
          ? CLILocalized.format(
            "cli.controller.rumble.stopped",
            device.name
          )
          : CLILocalized.format(
            "cli.controller.rumble.sent",
            ran.map { CommandLineName.kebab($0.rawValue) }.joined(separator: ", "),
            device.name
          )
      )
    }
  }
}

/// A player number from 1 to 4, or `off` (also `0`).
struct PlayerIndicatorArgument: ExpressibleByArgument, Equatable, Sendable {
  /// The player indicator that the argument names.
  let indicator: PhysicalPlayerIndicator

  /// Parses `argument`; fails when it is not a number from 0 to 4 or `off`.
  init?(argument: String) {
    if argument.lowercased() == "off" {
      indicator = .off
    } else if let number = Int(argument), let indicator = PhysicalPlayerIndicator(rawValue: number)
    {
      self.indicator = indicator
    } else {
      return nil
    }
  }

  /// The player indicator spellings that the command line accepts.
  static var allValueStrings: [String] { ["off", "1", "2", "3", "4"] }
}

/// The `ojd controller player` command: sets the player indicator lights of a controller.
struct ControllerPlayerCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "player",
    abstract: CLILocalized.text(
      "cli.controller.player.abstract"
    )
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// The controller to change.
  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  /// The player number from 1 to 4, or `off`.
  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.controller.player.number"),
      valueName: "number"
    )
  )
  var number: PlayerIndicatorArgument

  /// Runs the command.
  func run() async throws {
    try await global.run {
      try await sendOutput(
        [
          OutputRequest(
            name: "player",
            command: .setPlayerIndicator(number.indicator),
            feature: CLILocalized.text("cli.controller.group.featurePlayer")
          )
        ],
        to: controller
      )
    }
  }
}

/// A color as `RRGGBB` hex, with an optional leading `#`.
struct ColorArgument: ExpressibleByArgument, Equatable, Sendable {
  /// The parsed color.
  let color: ControllerColor

  /// Parses `argument`; fails when it is not a hex color.
  init?(argument: String) {
    guard let color = ControllerColor(hex: argument) else { return nil }
    self.color = color
  }

  /// Compares two arguments by their parsed color.
  static func == (lhs: Self, rhs: Self) -> Bool { lhs.color == rhs.color }
}

/// The `ojd controller light` command: sets the lightbar color or the LED brightness of a
/// controller.
struct ControllerLightCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "light",
    abstract: CLILocalized.text(
      "cli.controller.light.abstract"
    ),
    discussion: CLILocalized.text("cli.controller.light.examples")
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// The controller to change.
  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  /// `--color`: the lightbar color as `RRGGBB` hex.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text("cli.controller.light.color"),
      valueName: "RRGGBB"
    )
  )
  var color: ColorArgument?

  /// `--brightness`: the LED brightness, from 0 to 255.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text("cli.controller.light.brightness"),
      valueName: "0-255"
    )
  )
  var brightness: UInt8?

  /// Requires a color or a brightness.
  ///
  /// - Throws: ``ValidationError`` when the command names neither.
  func validate() throws {
    guard color != nil || brightness != nil else {
      throw ValidationError(
        CLILocalized.text(
          "cli.controller.light.errorMissing"
        )
      )
    }
  }

  /// Runs the command.
  func run() async throws {
    try await global.run {
      var requests: [OutputRequest] = []
      if let color {
        requests.append(
          OutputRequest(
            name: "color",
            command: .setRGB(color.color),
            feature: CLILocalized.text("cli.controller.group.featureColor")
          )
        )
      }
      if let brightness {
        requests.append(
          OutputRequest(
            name: "brightness",
            command: .setLightBrightness(UnipolarValue(byte: brightness)),
            feature: CLILocalized.text(
              "cli.controller.group.featureBrightness"
            )
          )
        )
      }
      try await sendOutput(requests, to: controller)
    }
  }
}
