import ArgumentParser
import Darwin
import Foundation
import OpenJoystickDriverKit

/// The `ojd service` command group: start or stop the service, or wait until it accepts requests.
struct ServiceCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "service",
    abstract: CLILocalized.text(
      "cli.service.group.abstract"
    ),
    subcommands: [ServiceStartCommand.self, ServiceStopCommand.self, ServiceWaitCommand.self]
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions
}

/// The `--json` result of the `service` commands.
struct ServiceStateResult: Encodable {
  /// Whether the service accepts requests.
  enum State: String, Encodable {
    /// The service accepts requests.
    case running = "Running"
    /// The service does not run.
    case stopped = "Stopped"
  }

  /// The state of the service.
  let state: State

  /// Prints `state` as JSON, as a `--plain` row, or `message` as a success line.
  static func print(_ state: State, message: @autoclosure () -> String) throws {
    switch CLIContext.current.format {
    case .json: try CLIOutput.json(Self(state: state))
    case .plain: CLIOutput.plain([["state", CommandLineName.kebab(state.rawValue)]])
    case .human: CLIOutput.success(message())
    }
  }
}

/// The `ojd service start` command: opens the app in the background and waits until its service
/// accepts requests.
///
/// It does nothing when the service already runs.
struct ServiceStartCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "start",
    abstract: CLILocalized.text(
      "cli.service.start.abstract"
    )
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      if ServiceConnection.processIdentifier() == nil {
        try Self.launchApplication()
        try await ServiceWaitCommand.waitUntilReady(timeout: CLIContext.current.waitTimeout)
      }
      try ServiceStateResult.print(
        .running,
        message: CLILocalized.text("cli.service.group.running")
      )
    }
  }

  /// Opens the app bundle in the background.
  ///
  /// - Throws: ``CLIFailure`` when the app bundle cannot be found or opened.
  private static func launchApplication() throws {
    guard let bundle = applicationBundleURL() else {
      throw CLIFailure(
        .installationProblem,
        CLILocalized.text(
          "cli.service.start.noBundle"
        )
      )
    }
    guard try BuildIdentity.openInBackground(bundle) else {
      throw CLIFailure(
        .systemRequestFailed,
        CLILocalized.format(
          "platform.macos.cli.service.start.openFailed",
          bundle.path
        )
      )
    }
  }

  /// The app bundle that contains this executable, following an installed `ojd` link.
  static func applicationBundleURL(executableURL: URL? = Bundle.main.executableURL) -> URL? {
    BuildIdentity.applicationBundleURL(executableURL: executableURL)
  }
}

/// The `ojd service stop` command: stops the service and waits until it exits.
struct ServiceStopCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "stop",
    abstract: CLILocalized.text(
      "platform.macos.cli.service.stop.abstract"
    )
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      if let processIdentifier = ServiceConnection.processIdentifier() {
        guard kill(processIdentifier, SIGTERM) == 0 || errno == ESRCH else {
          throw unsafe CLIFailure(
            .systemRequestFailed,
            CLILocalized.format(
              "cli.service.stop.signalFailed",
              String(cString: strerror(errno))
            )
          )
        }
        try await Self.waitUntilStopped(timeout: CLIContext.current.waitTimeout)
      }
      try ServiceStateResult.print(
        .stopped,
        message: CLILocalized.text("cli.service.group.stopped")
      )
    }
  }

  /// Waits until no service answers on the socket.
  ///
  /// - Throws: ``CLIFailure`` when `timeout` seconds pass first.
  private static func waitUntilStopped(timeout: Double) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while ServiceConnection.processIdentifier() != nil {
      guard Date() < deadline else {
        throw CLIFailure(
          .serviceTimeout,
          CLILocalized.format(
            "cli.service.stop.timeout",
            timeout.durationText
          )
        )
      }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
  }
}

/// The `ojd service wait` command: waits until the service accepts requests.
///
/// It exits with code 69 when the time runs out.
struct ServiceWaitCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "wait",
    abstract: CLILocalized.text(
      "cli.service.wait.abstract"
    )
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      try await Self.waitUntilReady(timeout: CLIContext.current.waitTimeout)
      try ServiceStateResult.print(
        .running,
        message: CLILocalized.text("cli.service.group.running")
      )
    }
  }

  /// Returns once the service answers a status request; exits 69 when `timeout` passes first.
  static func waitUntilReady(timeout: Double) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while true {
      let remaining = deadline.timeIntervalSinceNow
      guard remaining > 0 else { break }
      do {
        _ = try await ServiceConnection.request(timeout: remaining) { try await $0.getStatus() }
        return
      } catch let failure as CLIFailure where failure != .peerRejected {
        // Not running yet, or still starting: retry until the deadline.
        try await Task.sleep(nanoseconds: 100_000_000)
      }
    }
    throw CLIFailure(
      .serviceUnavailable,
      CLILocalized.format(
        "cli.service.wait.timeout",
        timeout.durationText
      )
    )
  }
}
