import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `--json` result of `ojd controller rumble`, `light`, and `player`.
struct ControllerOutputReport: Encodable, Equatable {
  struct Entry: Encodable, Equatable {
    let command: String
    let outcome: String
    let droppedRumbleChannels: [String]
  }

  let controller: String
  let results: [Entry]
}

/// One output command and the words that name it in a failure.
private struct OutputRequest: Sendable {
  let name: String
  let command: ControllerOutputCommand
  let feature: String
}

/// Sends each request to `selector`'s controller in order and prints the report.
///
/// Fails at the first request the controller does not deliver.
private func sendOutput(_ requests: [OutputRequest], to selector: ControllerSelector) async throws {
  let entries = try await ServiceConnection.request { client in
    let device = try await selector.resolve(with: client)
    var entries: [ControllerOutputReport.Entry] = []
    for request in requests {
      let result = try await client.sendControllerOutput(
        request.command,
        vendorID: device.vendorID,
        productID: device.productID,
        runtimeIdentifier: device.runtimeIdentifier
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
  let report = ControllerOutputReport(controller: entries.0.runtimeIdentifier, results: entries.1)
  switch CLIContext.current.format {
  case .json: try CLIOutput.json(report)
  case .plain:
    CLIOutput.plain(
      report.results.map {
        [$0.command, $0.outcome, $0.droppedRumbleChannels.joined(separator: ",")]
      }
    )
  case .human:
    CLIOutput.success(
      CLILocalized.format(
        "cli.controller.output.sent",
        report.results.map(\.command).joined(separator: ", "),
        entries.0.name
      )
    )
  }
}

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
        "cli.controller.output.unsupported",
        device.name,
        request.feature,
        device.runtimeIdentifier
      )
    )
  case .notReady:
    throw CLIFailure(
      .controllerRequestFailed,
      CLILocalized.format(
        "cli.controller.output.not_ready",
        device.name
      )
    )
  case .notFound, .cancelled:
    throw CLIFailure(
      .controllerRequestFailed,
      CLILocalized.format(
        "cli.controller.output.gone",
        device.name
      )
    )
  case .invalidValue, .writeFailed:
    throw CLIFailure(
      .controllerRequestFailed,
      CLILocalized.format(
        "cli.controller.output.failed",
        device.name,
        request.name,
        ControllerShowCommand.kebabCase(result.outcome.rawValue)
      )
    )
  }
}

struct ControllerRumbleCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "rumble",
    abstract: CLILocalized.text(
      "cli.controller.rumble.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.controller.rumble.discussion"
    )
  )

  @OptionGroup
  var global: GlobalOptions

  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  @Option(help: intensityHelp("cli.controller.rumble.left"))
  var left: UInt8?

  @Option(help: intensityHelp("cli.controller.rumble.right"))
  var right: UInt8?

  @Option(
    help: intensityHelp("cli.controller.rumble.left_trigger")
  )
  var leftTrigger: UInt8?

  @Option(
    help: intensityHelp("cli.controller.rumble.right_trigger")
  )
  var rightTrigger: UInt8?

  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.controller.rumble.duration"
      ),
      valueName: "seconds"
    )
  )
  var duration = 0.45

  private static func intensityHelp(_ key: String) -> ArgumentHelp {
    ArgumentHelp(CLILocalized.text(key), valueName: "0-255")
  }

  func validate() throws {
    guard duration.isFinite, duration > 0, duration <= 5 else {
      throw ValidationError(
        CLILocalized.text(
          "cli.controller.rumble.error.duration"
        )
      )
    }
  }

  /// The requested intensities; both main motors at 180 when no option names one.
  var intensities: RumbleIntensities {
    let noneGiven = [left, right, leftTrigger, rightTrigger].allSatisfy { $0 == nil }
    let fallback: UInt8 = noneGiven ? 180 : 0
    return RumbleIntensities(
      leftMain: UnipolarValue(byte: left ?? fallback),
      rightMain: UnipolarValue(byte: right ?? fallback),
      leftTrigger: UnipolarValue(byte: leftTrigger ?? 0),
      rightTrigger: UnipolarValue(byte: rightTrigger ?? 0)
    )
  }

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
      let feature = CLILocalized.text("cli.controller.feature.rumble")
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
        vendorID: device.vendorID,
        productID: device.productID,
        runtimeIdentifier: device.runtimeIdentifier
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
      case .leftMain: !dropped.contains(.leftMain) || !dropped.contains(.leftHaptic)
      case .rightMain: !dropped.contains(.rightMain) || !dropped.contains(.rightHaptic)
      default: !dropped.contains(motor)
      }
    }
    for motor in droppedTriggers {
      CLIOutput.stderr(
        CLILocalized.format(
          "cli.controller.rumble.dropped",
          device.name,
          ControllerShowCommand.kebabCase(motor.rawValue)
        )
      )
    }
    if !requested.isEmpty, ran.isEmpty {
      throw CLIFailure(
        .controllerRequestFailed,
        CLILocalized.format(
          "cli.controller.rumble.none_ran",
          device.name,
          device.runtimeIdentifier
        )
      )
    }
    let report = ControllerOutputReport(
      controller: device.runtimeIdentifier,
      results: [
        ControllerOutputReport.Entry(
          command: request.name,
          outcome: result.outcome.rawValue,
          droppedRumbleChannels: result.droppedRumbleChannels.map(\.rawValue)
        )
      ]
    )
    switch CLIContext.current.format {
    case .json: try CLIOutput.json(report)
    case .plain:
      CLIOutput.plain([
        [
          request.name, result.outcome.rawValue,
          droppedTriggers.map(\.rawValue).joined(separator: ","),
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
            ran.map { ControllerShowCommand.kebabCase($0.rawValue) }.joined(separator: ", "),
            device.name
          )
      )
    }
  }
}

/// A player number from 1 to 4, or `off` (also `0`).
struct PlayerIndicatorArgument: ExpressibleByArgument, Equatable, Sendable {
  let indicator: PhysicalPlayerIndicator

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

  static var allValueStrings: [String] { ["off", "1", "2", "3", "4"] }
}

struct ControllerPlayerCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "player",
    abstract: CLILocalized.text(
      "cli.controller.player.abstract"
    )
  )

  @OptionGroup
  var global: GlobalOptions

  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.controller.player.number"),
      valueName: "number"
    )
  )
  var number: PlayerIndicatorArgument

  func run() async throws {
    try await global.run {
      try await sendOutput(
        [
          OutputRequest(
            name: "player",
            command: .setPlayerIndicator(number.indicator),
            feature: CLILocalized.text("cli.controller.feature.player")
          )
        ],
        to: controller
      )
    }
  }
}

/// A color as `RRGGBB` hex, with an optional leading `#`.
struct ColorArgument: ExpressibleByArgument, Equatable, Sendable {
  let color: ControllerColor

  init?(argument: String) {
    let hex = argument.hasPrefix("#") ? String(argument.dropFirst()) : argument
    guard hex.count == 6, hex.allSatisfy(\.isHexDigit), let value = UInt32(hex, radix: 16) else {
      return nil
    }
    color = ControllerColor(
      red: UInt8(value >> 16 & 0xFF),
      green: UInt8(value >> 8 & 0xFF),
      blue: UInt8(value & 0xFF)
    )
  }

  static func == (lhs: Self, rhs: Self) -> Bool { lhs.color == rhs.color }
}

struct ControllerLightCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "light",
    abstract: CLILocalized.text(
      "cli.controller.light.abstract"
    )
  )

  @OptionGroup
  var global: GlobalOptions

  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  @Option(
    help: ArgumentHelp(
      CLILocalized.text("cli.controller.light.color"),
      valueName: "RRGGBB"
    )
  )
  var color: ColorArgument?

  @Option(
    help: ArgumentHelp(
      CLILocalized.text("cli.controller.light.brightness"),
      valueName: "0-255"
    )
  )
  var brightness: UInt8?

  func validate() throws {
    guard color != nil || brightness != nil else {
      throw ValidationError(
        CLILocalized.text(
          "cli.controller.light.error.missing"
        )
      )
    }
  }

  func run() async throws {
    try await global.run {
      var requests: [OutputRequest] = []
      if let color {
        requests.append(
          OutputRequest(
            name: "color",
            command: .setRGB(color.color),
            feature: CLILocalized.text("cli.controller.feature.color")
          )
        )
      }
      if let brightness {
        requests.append(
          OutputRequest(
            name: "brightness",
            command: .setLightBrightness(UnipolarValue(byte: brightness)),
            feature: CLILocalized.text(
              "cli.controller.feature.brightness"
            )
          )
        )
      }
      try await sendOutput(requests, to: controller)
    }
  }
}
