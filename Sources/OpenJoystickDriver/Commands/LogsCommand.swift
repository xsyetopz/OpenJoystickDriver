import AppKit
import Foundation
import OpenJoystickDriverKit

struct LogsCommand {
  private enum Selection: String {
    case stdout
    case stderr
    case both
  }

  private struct Options {
    var action = "show"
    var selection = Selection.both
    var maximumLines = ApplicationServiceLogService.defaultMaximumLines
    var json = false
  }

  func run(arguments: [String]) {
    let options = parse(arguments)
    switch options.action {
    case "show": show(options)
    case "path": printPaths(options.selection)
    case "open": open(options.selection)
    default: break
    }
  }

  private func show(_ options: Options) {
    let streams = streams(for: options.selection)
    do {
      let snapshots = try streams.map {
        try ApplicationServiceLogService.tail(stream: $0, maximumLines: options.maximumLines)
      }
      warnAboutLogs(json: options.json)
      if options.json {
        try printJSON(snapshots)
        return
      }
      for snapshot in snapshots {
        CLIOutput.diagnostic("== \(snapshot.stream.rawValue): \(snapshot.path) ==")
        if !snapshot.exists {
          CLIOutput.diagnostic("(log file does not exist)")
        } else if snapshot.lines.isEmpty {
          CLIOutput.diagnostic("(log file is empty)")
        } else {
          for line in snapshot.lines { CLIOutput.diagnostic(line) }
        }
        if snapshot.truncated { CLIOutput.diagnostic("(earlier log content omitted)") }
      }
    } catch {
      CLIOutput.error(error.localizedDescription)
      exit(1)
    }
  }

  private func printPaths(_ selection: Selection) {
    for stream in streams(for: selection) {
      CLIOutput.diagnostic(ApplicationServiceLogService.url(for: stream).path)
    }
  }

  private func open(_ selection: Selection) {
    for stream in streams(for: selection) {
      let path = ApplicationServiceLogService.url(for: stream).path
      NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
  }

  private func streams(for selection: Selection) -> [ApplicationServiceLogStream] {
    switch selection {
    case .stdout: return [.standardOutput]
    case .stderr: return [.standardError]
    case .both: return [.standardOutput, .standardError]
    }
  }

  private func printJSON(_ snapshots: [ApplicationServiceLogSnapshot]) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(snapshots)
    print(String(data: data, encoding: .utf8) ?? "[]")
  }

  private func warnAboutLogs(json: Bool) {
    if json {
      FileHandle.standardError.write(
        Data("WARNING: \(ApplicationServiceLogService.sharingWarning)\n".utf8)
      )
    } else {
      CLIOutput.warning(ApplicationServiceLogService.sharingWarning)
    }
  }

  private func parse(_ arguments: [String]) -> Options {
    var options = Options()
    var index = 0
    if let first = arguments.first, ["show", "path", "open"].contains(first) {
      options.action = first
      index = 1
    } else if let first = arguments.first, ["--help", "-h", "help"].contains(first) {
      printHelp()
      exit(0)
    }

    while index < arguments.count {
      let argument = arguments[index]
      switch argument {
      case "--stream":
        guard index + 1 < arguments.count, let selection = Selection(rawValue: arguments[index + 1])
        else {
          CLIOutput.error("--stream must be stdout, stderr, or both.")
          exit(1)
        }
        options.selection = selection
        index += 2
      case "--lines" where options.action == "show":
        guard index + 1 < arguments.count, let lines = Int(arguments[index + 1]),
          (1...10_000).contains(lines)
        else {
          CLIOutput.error("--lines must be 1...10000.")
          exit(1)
        }
        options.maximumLines = lines
        index += 2
      case "--json" where options.action == "show":
        options.json = true
        index += 1
      case "--help", "-h", "help":
        printHelp()
        exit(0)
      default:
        CLIOutput.error("Unknown logs option: \(argument)")
        printHelp()
        exit(1)
      }
    }
    return options
  }

  private func printHelp() {
    print(
      [
        "Usage: OpenJoystickDriver --headless app logs <show|path|open> [options]", "", "Options:",
        "  --stream stdout|stderr|both",
        "  --lines 1...10000       Tail limit for show (default 100)",
        "  --json                   Emit typed snapshots for show", "",
        "Log reads retain at most 256 KiB per file and warn before sharing.",
      ].joined(separator: "\n")
    )
  }
}
