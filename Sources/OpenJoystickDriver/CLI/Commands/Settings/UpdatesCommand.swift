import AppKit
import Foundation
import OpenJoystickDriverKit

struct UpdatesCommand {
  private struct Options {
    var includePrereleases = false
    var json = false
    var openRelease = false
  }

  private struct JSONOutput: Encodable {
    let status: String
    let currentVersion: String
    let latestTag: String?
    let releaseURL: String?
    let includePrereleases: Bool
    let message: String?
  }

  func run(arguments: [String]) {
    let options = parse(arguments)
    let currentVersion = ApplicationVersion.current
    let state = runSyncResult {
      await UpdateChecker().check(
        currentVersion: currentVersion,
        includePrereleases: options.includePrereleases
      )
    }

    if options.json {
      printJSON(state, currentVersion: currentVersion, options: options)
    } else {
      printText(state, currentVersion: currentVersion, options: options)
    }

    if options.openRelease, case .available(let info) = state {
      NSWorkspace.shared.open(info.htmlURL)
    }
    if case .failed = state { exit(1) }
  }

  private func printText(_ state: UpdateCheckState, currentVersion: String, options: Options) {
    print(CLILocalized.text("cli.updates.heading", "OpenJoystickDriver Update Check"))
    print(CLILocalized.format("cli.updates.current_label", "  Current     : %@", currentVersion))
    let prereleaseStatus =
      options.includePrereleases
      ? CLILocalized.text("cli.updates.included", "included")
      : CLILocalized.text("cli.updates.excluded", "excluded")
    print(
      CLILocalized.format("cli.updates.prereleases_label", "  Prereleases : %@", prereleaseStatus)
    )
    switch state {
    case .upToDate(let latestTag):
      print(
        CLILocalized.format(
          "cli.updates.status_none",
          "  Status      : %@",
          CLILocalized.text("cli.updates.none", "no update available")
        )
      )
      print(CLILocalized.format("cli.updates.latest_label", "  Latest      : %@", latestTag))
    case .available(let info):
      print(
        CLILocalized.format(
          "cli.updates.status_available",
          "  Status      : %@",
          CLILocalized.text("cli.updates.available", "update available")
        )
      )
      print(CLILocalized.format("cli.updates.latest_label", "  Latest      : %@", info.tagName))
      print(
        CLILocalized.format(
          "cli.updates.release_label",
          "  Release     : %@",
          info.htmlURL.absoluteString
        )
      )
    case .failed(let message):
      print(
        CLILocalized.format(
          "cli.updates.status_failed",
          "  Status      : %@",
          CLILocalized.text("cli.updates.failed", "failed")
        )
      )
      print(CLILocalized.format("cli.updates.error_label", "  Error       : %@", message))
    case .idle, .checking:
      print(
        CLILocalized.format(
          "cli.updates.status_incomplete",
          "  Status      : %@",
          CLILocalized.text("cli.updates.incomplete", "incomplete")
        )
      )
    }
  }

  private func printJSON(_ state: UpdateCheckState, currentVersion: String, options: Options) {
    let output: JSONOutput
    switch state {
    case .upToDate(let latestTag):
      output = JSONOutput(
        status: "upToDate",
        currentVersion: currentVersion,
        latestTag: latestTag,
        releaseURL: nil,
        includePrereleases: options.includePrereleases,
        message: nil
      )
    case .available(let info):
      output = JSONOutput(
        status: "available",
        currentVersion: currentVersion,
        latestTag: info.tagName,
        releaseURL: info.htmlURL.absoluteString,
        includePrereleases: options.includePrereleases,
        message: nil
      )
    case .failed(let message):
      output = JSONOutput(
        status: "failed",
        currentVersion: currentVersion,
        latestTag: nil,
        releaseURL: nil,
        includePrereleases: options.includePrereleases,
        message: message
      )
    case .idle, .checking:
      output = JSONOutput(
        status: "incomplete",
        currentVersion: currentVersion,
        latestTag: nil,
        releaseURL: nil,
        includePrereleases: options.includePrereleases,
        message: nil
      )
    }

    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(output)
      print(String(data: data, encoding: .utf8) ?? "{}")
    } catch {
      print("{\"status\":\"failed\",\"message\":\"JSON encoding failed\"}")
      exit(1)
    }
  }

  private func parse(_ arguments: [String]) -> Options {
    var arguments = arguments
    if arguments.first == "check" { arguments.removeFirst() }
    if let first = arguments.first, ["--help", "-h", "help"].contains(first) {
      printHelp()
      exit(0)
    }

    var options = Options()
    for argument in arguments {
      switch argument {
      case "--prerelease": options.includePrereleases = true
      case "--json": options.json = true
      case "--open": options.openRelease = true
      default:
        CLIOutput.error(
          CLILocalized.format("cli.updates.unknown_option", "Unknown updates option: %@", argument)
        )
        printHelp()
        exit(1)
      }
    }
    return options
  }

  private func printHelp() {
    print(
      CLILocalized.text(
        "cli.updates.help",
        """
        Usage: OpenJoystickDriver --headless update check [options]

        Options:
          --prerelease  Include SemVer prerelease tags
          --json        Emit machine-readable JSON
          --open        Open the release page only when an update is available

        This command checks GitHub tags; it does not download or install an update.
        """
      )
    )
  }
}
