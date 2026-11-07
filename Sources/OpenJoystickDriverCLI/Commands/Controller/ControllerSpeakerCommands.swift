import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd controller speaker` group: plays a clip on a controller's speaker or stops it.
struct ControllerSpeakerCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "speaker",
    abstract: CLILocalized.text("cli.controller.speaker.abstract"),
    subcommands: [ControllerSpeakerPlayCommand.self, ControllerSpeakerStopCommand.self]
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions
}

/// The request that names the speaker in a failure message.
private let speakerRequest = OutputRequest(
  name: "speaker",
  command: .speaker(.stop),
  feature: CLILocalized.text("cli.controller.group.featureSpeaker")
)

/// The speaker format of `device`.
///
/// - Throws: ``CLIFailure`` with `SpeakerUnavailable` when the controller has no speaker.
private func speakerFormat(
  of device: ApplicationServiceDeviceDescription
) throws -> PhysicalSpeakerFormat {
  guard let format = device.physicalOutputCapabilities.speaker else {
    throw CLIFailure(.speakerUnavailable, CLILocalized.text("error.E2038.message"))
  }
  return format
}

/// Prints the one-line result of a speaker command.
private func printSpeakerResult(
  _ outcome: ControllerOutputResult.Outcome,
  of device: ApplicationServiceDeviceDescription,
  human: String
) throws {
  switch CLIContext.current.format {
  case .json:
    try CLIOutput.json(
      CLIStatus(
        details: ControllerOutputReport(
          controller: device.sessionToken.rawValue,
          results: [
            ControllerOutputReport.Entry(
              command: speakerRequest.name,
              outcome: outcome.rawValue,
              droppedRumbleChannels: []
            )
          ]
        )
      )
    )
  case .plain: CLIOutput.plain([[speakerRequest.name, CommandLineName.kebab(outcome.rawValue)]])
  case .human: CLIOutput.success(human)
  }
}

/// The `ojd controller speaker play` command: plays a PCM WAV file on a controller's speaker.
struct ControllerSpeakerPlayCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "play",
    abstract: CLILocalized.text("cli.controller.speaker.play.abstract")
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// The controller to play on.
  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  /// The PCM WAV file to play.
  @Argument(
    help: ArgumentHelp(CLILocalized.text("cli.controller.speaker.play.file"), valueName: "file")
  )
  var file: String

  /// `--volume`: the playback volume, from 0 to 1.
  @Option(
    help: ArgumentHelp(CLILocalized.text("cli.controller.speaker.play.volume"), valueName: "0-1")
  )
  var volume = 1.0

  /// Checks that the volume is a number from 0 to 1.
  func validate() throws {
    guard volume.isFinite, (0...1).contains(volume) else {
      throw ValidationError(CLILocalized.text("cli.controller.speaker.play.errorVolume"))
    }
  }

  /// Runs the command.
  ///
  /// The service returns when the clip ends, so the request deadline is the `--timeout` plus the
  /// clip length.
  func run() async throws {
    try await global.run {
      let wav: Data
      do { wav = try Data(contentsOf: URL(fileURLWithPath: file)) } catch {
        throw CLIFailure.usage(
          CLILocalized.format(
            "cli.controller.speaker.play.errorUnreadable",
            file,
            error.localizedDescription
          )
        )
      }
      let selector = controller
      let device = try await ServiceConnection.request { try await selector.resolve(with: $0) }
      let format = try speakerFormat(of: device)
      guard let limit = device.tuning.speakerMaxSeconds else {
        throw CLIFailure(.speakerUnavailable, CLILocalized.text("error.E2038.message"))
      }
      let audio: SpeakerAudio
      do {
        audio = try SpeakerAudio(
          wav: wav,
          rate: format.sampleRate,
          maxSeconds: limit,
          volume: volume
        )
      } catch {
        throw CLIFailure(.unsupportedAudioFile, CLILocalized.text("error.E2039.message"))
      }
      if audio.isTrimmed {
        CLIOutput.stderr(
          CLILocalized.format("cli.controller.speaker.play.trimmed", String(limit))
        )
      }
      let encoded = Data(format.encode(audio.samples))
      let result = try await ServiceConnection.request(
        timeout: CLIContext.current.requestTimeout + Double(limit)
      ) { client in
        try await client.playControllerSpeaker(encoded, for: .session(device.sessionToken))
      }
      if result.outcome != .cancelled { try check(result, speakerRequest, device) }
      try printSpeakerResult(
        result.outcome,
        of: device,
        human: result.outcome == .cancelled
          ? CLILocalized.format("cli.controller.speaker.play.stopped", device.name)
          : CLILocalized.format(
            "cli.controller.speaker.play.played",
            URL(fileURLWithPath: file).lastPathComponent,
            device.name
          )
      )
    }
  }
}

/// The `ojd controller speaker stop` command: cuts the clip playing on a controller's speaker.
struct ControllerSpeakerStopCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "stop",
    abstract: CLILocalized.text("cli.controller.speaker.stop.abstract")
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// The controller to stop.
  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let selector = controller
      let (device, result) = try await ServiceConnection.request { client in
        let device = try await selector.resolve(with: client)
        _ = try speakerFormat(of: device)
        return (device, try await client.stopControllerSpeaker(for: .session(device.sessionToken)))
      }
      try check(result, speakerRequest, device)
      try printSpeakerResult(
        result.outcome,
        of: device,
        human: CLILocalized.format("cli.controller.speaker.stop.stopped", device.name)
      )
    }
  }
}
