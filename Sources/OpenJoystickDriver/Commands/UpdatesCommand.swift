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
    print("OpenJoystickDriver Update Check")
    print("  Current     : \(currentVersion)")
    print("  Prereleases : \(options.includePrereleases ? "included" : "excluded")")
    switch state {
    case .upToDate(let latestTag):
      print("  Status      : no update available")
      print("  Latest      : \(latestTag)")
    case .available(let info):
      print("  Status      : update available")
      print("  Latest      : \(info.tagName)")
      print("  Release     : \(info.htmlURL.absoluteString)")
    case .failed(let message):
      print("  Status      : failed")
      print("  Error       : \(message)")
    case .idle, .checking: print("  Status      : incomplete")
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
        print("Unknown updates option: \(argument)")
        printHelp()
        exit(1)
      }
    }
    return options
  }

  private func printHelp() {
    print(
      [
        "Usage: OpenJoystickDriver --headless update check [options]", "", "Options:",
        "  --prerelease  Include SemVer prerelease tags",
        "  --json        Emit machine-readable JSON",
        "  --open        Open the release page only when an update is available", "",
        "This command checks GitHub tags; it does not download or install an update.",
      ].joined(separator: "\n")
    )
  }
}
