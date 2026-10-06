import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct UpdateCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "update",
    abstract: CLILocalized.text(
      "cli.update.abstract"
    ),
    subcommands: [UpdateCheckCommand.self]
  )

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions
}

struct UpdateCheckCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "check",
    abstract: CLILocalized.text(
      "cli.update.check.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.update.check.discussion"
    )
  )

  /// Asks GitHub for the latest release; tests replace it to stay offline.
  @TaskLocal
  static var checker:
    @Sendable (_ currentVersion: String, _ includePrereleases: Bool) async -> UpdateCheckState = {
      current,
      prereleases in
      await UpdateChecker().check(currentVersion: current, includePrereleases: prereleases)
    }

  @Flag(
    help: ArgumentHelp(
      CLILocalized.text("cli.update.check.prerelease")
    )
  )
  var prerelease = false

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// The `--json` result.
  struct Result: Encodable, Equatable {
    enum Status: String, Encodable {
      case upToDate = "up-to-date"
      case available
    }

    let status: Status
    let currentVersion: String
    let latestVersion: String
    let releaseURL: String?
    let includePrereleases: Bool
  }

  func run() async throws {
    try await global.run {
      let current = ApplicationVersion.current
      let result: Result
      switch await Self.checker(current, prerelease) {
      case .upToDate(let latest):
        result = Result(
          status: .upToDate,
          currentVersion: current,
          latestVersion: latest,
          releaseURL: nil,
          includePrereleases: prerelease
        )
      case .available(let info):
        result = Result(
          status: .available,
          currentVersion: current,
          latestVersion: info.tagName,
          releaseURL: info.htmlURL.absoluteString,
          includePrereleases: prerelease
        )
      case .failed(let failure):
        throw Self.failure(failure.message, network: failure.reason == .transport)
      case .idle, .checking:
        throw Self.failure(
          CLILocalized.text("cli.update.check.incomplete"),
          network: false
        )
      }
      try Self.print(result)
    }
  }

  private static func print(_ result: Result) throws {
    switch CLIContext.current.format {
    case .json: try CLIOutput.json(result)
    case .plain:
      CLIOutput.plain([
        [
          result.status.rawValue, result.currentVersion, result.latestVersion,
          result.releaseURL ?? "",
        ]
      ])
    case .human:
      switch result.status {
      case .upToDate:
        CLIOutput.stdout(
          CLILocalized.format(
            "cli.update.check.up_to_date",
            result.currentVersion,
            result.latestVersion
          )
        )
      case .available:
        CLIOutput.stdout(
          CLILocalized.format(
            "cli.update.check.available",
            result.latestVersion,
            result.currentVersion,
            result.releaseURL ?? ""
          )
        )
      }
    }
  }

  /// Only a network failure points at the connection; other failures state their reason alone.
  private static func failure(_ detail: String, network: Bool) -> CLIFailure {
    let message =
      network
      ? CLILocalized.format(
        "cli.update.check.failed",
        detail
      )
      : CLILocalized.format(
        "cli.update.check.failed_reason",
        detail
      )
    return CLIFailure(.updateCheckFailed, message)
  }
}
