import ArgumentParser
import Darwin
import Foundation
import OpenJoystickDriverKit

struct ServiceCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "service",
    abstract: CLILocalized.text(
      "cli.service.abstract"
    ),
    subcommands: [ServiceStartCommand.self, ServiceStopCommand.self, ServiceWaitCommand.self]
  )

  @OptionGroup
  var global: GlobalOptions
}

/// The `--json` result of the `service` commands.
struct ServiceStateResult: Encodable {
  enum State: String, Encodable {
    case running
    case stopped
  }

  let state: State

  static func print(_ state: State, message: @autoclosure () -> String) throws {
    switch CLIContext.current.format {
    case .json: try CLIOutput.json(Self(state: state))
    case .plain: CLIOutput.plain([["state", state.rawValue]])
    case .human: CLIOutput.success(message())
    }
  }
}

struct ServiceStartCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "start",
    abstract: CLILocalized.text(
      "cli.service.start.abstract"
    )
  )

  @OptionGroup
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      if ServiceConnection.processIdentifier() == nil {
        try Self.launchApplication()
        try await ServiceWaitCommand.waitUntilReady(timeout: CLIContext.current.waitTimeout)
      }
      try ServiceStateResult.print(
        .running,
        message: CLILocalized.text("cli.service.running")
      )
    }
  }

  private static func launchApplication() throws {
    guard let bundle = applicationBundleURL() else {
      throw CLIFailure(
        .installationProblem,
        CLILocalized.text(
          "cli.service.start.no_bundle"
        )
      )
    }
    let result = try BoundedProcessRunner.run(
      executableURL: URL(fileURLWithPath: "/usr/bin/open"),
      arguments: ["-g", bundle.path],
      timeoutSeconds: 10,
      maximumOutputBytes: 16_384
    )
    guard result.terminationStatus == 0, !result.timedOut else {
      throw CLIFailure(
        .systemRequestFailed,
        CLILocalized.format(
          "cli.service.start.open_failed",
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

struct ServiceStopCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "stop",
    abstract: CLILocalized.text(
      "cli.service.stop.abstract"
    )
  )

  @OptionGroup
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      if let processIdentifier = ServiceConnection.processIdentifier() {
        guard kill(processIdentifier, SIGTERM) == 0 || errno == ESRCH else {
          throw CLIFailure(
            .systemRequestFailed,
            CLILocalized.format(
              "cli.service.stop.signal_failed",
              String(cString: strerror(errno))
            )
          )
        }
        try await Self.waitUntilStopped(timeout: CLIContext.current.waitTimeout)
      }
      try ServiceStateResult.print(
        .stopped,
        message: CLILocalized.text("cli.service.stopped")
      )
    }
  }

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

struct ServiceWaitCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "wait",
    abstract: CLILocalized.text(
      "cli.service.wait.abstract"
    )
  )

  @OptionGroup
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      try await Self.waitUntilReady(timeout: CLIContext.current.waitTimeout)
      try ServiceStateResult.print(
        .running,
        message: CLILocalized.text("cli.service.running")
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
