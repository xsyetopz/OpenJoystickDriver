import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct UpdateCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "update",
    abstract: CLILocalized.text(
      "cli.update.abstract",
      "Check whether a newer OpenJoystickDriver release exists."
    ),
    subcommands: [UpdateCheckCommand.self]
  )

  @OptionGroup
  var global: GlobalOptions
}

struct UpdateCheckCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "check",
    abstract: CLILocalized.text(
      "cli.update.check.abstract",
      "Compare this version with the latest release tag on GitHub."
    ),
    discussion: CLILocalized.text(
      "cli.update.check.discussion",
      "Runs only when you ask; ojd never checks on its own. It does not download or install "
        + "anything. Exits 0 whether or not an update exists, and 1 when the check fails."
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
      CLILocalized.text("cli.update.check.prerelease", "Include pre-release versions.")
    )
  )
  var prerelease = false

  @OptionGroup
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
      case .failed(let failure): throw Self.failure(failure.message)
      case .idle, .checking:
        throw Self.failure(CLILocalized.text("cli.update.check.incomplete", "no result"))
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
            "OpenJoystickDriver %@ is up to date (latest release: %@).",
            result.currentVersion,
            result.latestVersion
          )
        )
      case .available:
        CLIOutput.stdout(
          CLILocalized.format(
            "cli.update.check.available",
            "OpenJoystickDriver %@ is available (you have %@): %@",
            result.latestVersion,
            result.currentVersion,
            result.releaseURL ?? ""
          )
        )
      }
    }
  }

  private static func failure(_ detail: String) -> CLIFailure {
    CLIFailure(
      .failure,
      CLILocalized.format(
        "cli.update.check.failed",
        "Could not check for updates: %@. Check your network connection and try again.",
        detail
      )
    )
  }
}
