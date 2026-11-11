import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd virtual launch` command: runs a program with the environment set for virtual gamepads
/// and exits with its status.
struct VirtualLaunchCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "launch",
    abstract: CLILocalized.text("cli.virtual.launch.abstract"),
    discussion: CLILocalized.text("cli.virtual.launch.discussion")
  )

  /// The environment the program starts from; tests replace it.
  @TaskLocal
  static var baseEnvironment = ProcessInfo.processInfo.environment

  /// Where the program writes its standard output; nil leaves it on this process's standard output.
  ///
  /// Tests replace it to read what the program printed.
  @TaskLocal
  static var programStandardOutput: FileHandle?

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// `--sdl-gamecontroller-backend`: set the program up to use the SDL game controller backend.
  @Flag(
    name: .customLong("sdl-gamecontroller-backend"),
    help: ArgumentHelp(
      CLILocalized.text("platform.macos.cli.virtual.launch.sdlGamecontrollerBackend")
    )
  )
  var sdlGameControllerBackend = false

  /// The program and its arguments.
  @Argument(
    parsing: .remaining,
    help: ArgumentHelp(CLILocalized.text("cli.virtual.launch.command"), valueName: "program")
  )
  var command: [String] = []

  /// Runs the command.
  func run() async throws {
    try await global.run {
      // The program owns standard output, so there is no JSON or plain form.
      guard CLIContext.current.format == .human else {
        throw CLIFailure.usage(CLILocalized.text("cli.virtual.launch.errorOutput"))
      }
      guard let name = command.first else {
        throw CLIFailure.usage(CLILocalized.text("cli.virtual.launch.errorNoProgram"))
      }
      let executable = try ProgramLauncher.executable(
        for: name,
        searchPath: Self.baseEnvironment["PATH"]
      )
      let devices = try await ServiceConnection.request { client in
        try await client.getStatus().connectedDevices
      }
      let profiles = devices.compactMap { $0.servingDecision.selection?.profileID }
      let environment: [String: String]
      do {
        environment = try SDLLaunchEnvironment.environment(
          adding: profiles,
          to: Self.baseEnvironment,
          gameControllerBackend: sdlGameControllerBackend
        )
      } catch SDLLaunchEnvironment.Failure.noProfile {
        throw CLIFailure(
          .controllerRequestFailed,
          CLILocalized.text("cli.virtual.launch.errorNoGamepad")
        )
      }
      if !CLIContext.current.quiet, !sdlGameControllerBackend {
        for profile in VirtualHIDProfileID.allCases where profiles.contains(profile) {
          if try !profile.gamepadMapping().worksWithDefaultSDLHints {
            CLIOutput.stderr(sdlHintsNote(profile.rawValue))
          }
        }
      }
      let status = try await ProgramLauncher.run(
        executable: executable,
        arguments: Array(command.dropFirst()),
        environment: environment,
        standardOutput: Self.programStandardOutput
      )
      if status != 0 { throw ExitCode(status) }
    }
  }
}

/// Starts a program and waits for it.
enum ProgramLauncher {
  /// The file that runs for `name`; see ``ProgramExecutable``.
  static func executable(for name: String, searchPath: String?) throws -> URL {
    do { return try ProgramExecutable.url(for: name, searchPath: searchPath) } catch {
      let reason: String
      switch error as? ProgramExecutable.Failure {
      case .noExecutable?: reason = CLILocalized.text("cli.virtual.launch.errorNoExecutable")
      case .notExecutable?: reason = CLILocalized.text("cli.virtual.launch.errorNotExecutable")
      case .notFound?: reason = CLILocalized.text("cli.virtual.launch.errorNotFound")
      case nil: throw error
      }
      throw failure(name, reason)
    }
  }

  /// Runs `executable` with `environment` and the standard input, error, and output of this
  /// process, or `standardOutput` when given.
  ///
  /// Returns its exit status, or 128 plus the signal that ended it. Stopping `ojd` with SIGINT or
  /// SIGTERM ends the program with SIGTERM first.
  static func run(
    executable: URL,
    arguments: [String],
    environment: [String: String],
    standardOutput: FileHandle?
  ) async throws -> Int32 {
    let process = ProgramExecutable.process(
      executable: executable,
      arguments: arguments,
      environment: environment,
      standardOutput: standardOutput
    )
    let stop: @Sendable () async -> Void = { process.terminate() }
    return try await withCLIShutdownCleanup(stop) {
      try await withCheckedThrowingContinuation { continuation in
        process.terminationHandler = { finished in
          continuation.resume(
            returning: finished.terminationReason == .uncaughtSignal
              ? 128 + finished.terminationStatus : finished.terminationStatus
          )
        }
        do { try process.run() } catch {
          process.terminationHandler = nil
          continuation.resume(throwing: failure(executable.path, error.localizedDescription))
        }
      }
    }
  }

  /// Returns the failure for a program that did not start, with `reason`.
  private static func failure(_ program: String, _ reason: String) -> CLIFailure {
    CLIFailure(
      .launchFailed,
      CLILocalized.format("cli.virtual.launch.errorFailed", program, reason)
    )
  }
}
