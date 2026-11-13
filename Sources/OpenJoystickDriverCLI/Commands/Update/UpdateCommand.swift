import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd update` command group: checks for a release of OJD.
struct UpdateCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "update",
    abstract: CLILocalized.text(
      "cli.update.group.abstract"
    ),
    subcommands: [UpdateCheckCommand.self]
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions
}

/// The `ojd update check` command: asks GitHub for the latest release and compares it with the
/// installed version.
struct UpdateCheckCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
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

  /// `--prerelease`: consider prereleases as well as releases.
  @Flag(
    help: ArgumentHelp(
      CLILocalized.text("cli.update.check.prerelease")
    )
  )
  var prerelease = false

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// The `--json` result.
  struct Result: Encodable, Equatable {
    /// How the installed version compares with the latest release.
    enum Status: String, Encodable {
      /// The installed version is the latest release.
      case upToDate = "UpToDate"
      /// A later release exists.
      case available = "Available"
      /// The installed version is later than the latest release.
      case aheadOfLatestRelease = "AheadOfLatestRelease"
    }

    /// How the installed version compares with the latest release.
    let status: Status
    /// The installed version.
    let currentVersion: String
    /// The latest release version.
    let latestVersion: String
    /// The page of the later release, when there is one.
    let releaseURL: String?
    /// Whether prereleases were considered.
    let includePrereleases: Bool
  }

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let current = ApplicationVersion.current
      let result: Result
      switch await Self.checker(current, prerelease) {
      case .upToDate(_, let latest):
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
      case .aheadOfLatestRelease(_, let latest):
        result = Result(
          status: .aheadOfLatestRelease,
          currentVersion: current,
          latestVersion: latest,
          releaseURL: nil,
          includePrereleases: prerelease
        )
      case .failed(let failure):
        throw Self.failure(failure.message, network: failure.reason == .transport)
      case .onlyPrereleases:
        throw Self.failure(
          CLILocalized.text("cli.update.check.onlyPrereleases"),
          network: false
        )
      case .idle, .checking:
        throw Self.failure(
          CLILocalized.text("cli.update.check.incomplete"),
          network: false
        )
      }
      try Self.print(result)
    }
  }

  /// Prints `result` as JSON, as a `--plain` row, or as a sentence.
  private static func print(_ result: Result) throws {
    switch CLIContext.current.format {
    case .json: try CLIOutput.json(result)
    case .plain:
      CLIOutput.plain([
        [
          CommandLineName.kebab(result.status.rawValue), result.currentVersion,
          result.latestVersion,
          result.releaseURL ?? "",
        ]
      ])
    case .human:
      switch result.status {
      case .upToDate:
        CLIOutput.stdout(
          CLILocalized.format(
            "cli.update.check.upToDate",
            result.currentVersion,
            result.latestVersion
          )
        )
      case .aheadOfLatestRelease:
        CLIOutput.stdout(
          CLILocalized.format(
            "cli.update.check.ahead",
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

  /// Returns the failure for a check that did not finish, with `detail` as its reason.
  ///
  /// Only a network failure points at the connection; other failures state their reason alone.
  private static func failure(_ detail: String, network: Bool) -> CLIFailure {
    let message =
      network
      ? CLILocalized.format(
        "cli.update.check.failed",
        detail
      )
      : CLILocalized.format(
        "cli.update.check.failedReason",
        detail
      )
    return CLIFailure(.updateCheckFailed, message)
  }
}
