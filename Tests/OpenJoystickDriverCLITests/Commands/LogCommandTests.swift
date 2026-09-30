import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized)
struct LogCommandTests {
  private static func snapshot(
    _ stream: ApplicationServiceLogStream,
    _ lines: [String]
  ) -> ApplicationServiceLogSnapshot {
    ApplicationServiceLogSnapshot(
      stream: stream,
      path: "/logs/\(stream.rawValue).log",
      exists: true,
      fileSizeBytes: 10,
      lines: lines,
      truncated: false
    )
  }

  /// A log folder with one line per stream, a pager that records what it was given, and
  /// `followed` lines that each stream yields before it ends.
  private func environment(
    terminal: Bool,
    paged: Locked<[String]>,
    requestedLines: Locked<[Int]> = Locked([]),
    followed: [String] = []
  ) -> LogEnvironment {
    LogEnvironment(
      directory: { URL(fileURLWithPath: "/logs") },
      tail: { stream, lines in
        requestedLines.withLock { $0.append(lines) }
        return Self.snapshot(stream, ["\(stream.rawValue) line"])
      },
      follow: { stream, _ in
        AsyncStream { continuation in
          for text in followed { continuation.yield(LogLine(stream: stream, text: text)) }
          continuation.finish()
        }
      },
      page: { command, text in paged.withLock { $0.append(command + "|" + text) } },
      isTerminal: { terminal }
    )
  }

  private func run(_ arguments: [String], _ environment: LogEnvironment) async -> CLIRun {
    await LogCommand.$environment.withValue(environment) { await CLIRun.run(arguments) }
  }

  @Test
  func pathPrintsTheFolderWithoutTheService() async throws {
    let env = environment(terminal: false, paged: Locked([]))

    let human = await run(["log", "path"], env)
    let json = await run(["log", "path", "--json"], env)

    #expect(human.code == 0)
    #expect(human.standardOutput == "/logs\n")
    #expect(human.standardError.isEmpty)
    #expect(try json.json()["path"] as? String == "/logs")
  }

  @Test
  func showWritesToStandardOutputWhenNotATerminal() async throws {
    let paged = Locked<[String]>([])
    let requested = Locked<[Int]>([])
    let env = environment(terminal: false, paged: paged, requestedLines: requested)

    let human = await run(["log", "show", "-n", "7"], env)
    let json = await run(["log", "show", "--json"], env)
    let plain = await run(["log", "show", "--plain"], env)

    #expect(human.code == 0)
    #expect(human.standardOutput.contains("== standardOutput: /logs/standardOutput.log ==\n"))
    #expect(human.standardOutput.contains("standardError line\n"))
    #expect(human.standardError.contains(ApplicationServiceLogService.sharingWarning))
    #expect(requested.withLock { $0.prefix(2) } == [7, 7])
    let logs = try #require(try json.json()["logs"] as? [[String: Any]])
    #expect(logs.count == 2)
    #expect(
      plain.standardOutput
        == "standardOutput\tstandardOutput line\nstandardError\tstandardError line\n"
    )
    #expect(paged.withLock { $0.isEmpty })
  }

  @Test
  func showPagesOnlyOnATerminalInHumanFormat() async {
    let paged = Locked<[String]>([])
    let env = environment(terminal: true, paged: paged)

    let human = await run(["log", "show"], env)
    let json = await run(["log", "show", "--json"], env)

    #expect(human.code == 0)
    #expect(human.standardOutput.isEmpty)
    let pages = paged.withLock { $0 }
    #expect(pages.count == 1)
    #expect(pages.first?.contains("standardOutput line") == true)
    #expect(!json.standardOutput.isEmpty)
  }

  @Test
  func followStreamsLinesAndJSONLines() async throws {
    let paged = Locked<[String]>([])
    let env = environment(terminal: true, paged: paged, followed: ["new"])

    let human = await run(["log", "show", "--follow"], env)
    let json = await run(["log", "show", "-f", "--json"], env)

    #expect(human.code == 0, "\(human.standardError)")
    #expect(human.standardOutput.hasSuffix("new\nnew\n"))
    #expect(paged.withLock { $0.isEmpty })
    let records = json.standardOutput.split(separator: "\n").map { line in
      (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: String]
    }
    #expect(records.count == 4)
    #expect(records.allSatisfy { $0?["line"] != nil && $0?["stream"] != nil })
  }

  @Test(arguments: [["log", "show", "--lines", "0"], ["log", "show", "--lines", "10001"]])
  func linesOutOfRangeExitSixtyFour(arguments: [String]) async {
    let result = await run(arguments, environment(terminal: false, paged: Locked([])))

    #expect(result.code == 64)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.hasPrefix("ojd: "))
  }

  @Test
  func pagerCommandFollowsThePagerVariable() {
    #expect(LogShowCommand.pagerCommand(environment: [:]) == "less -FRX")
    #expect(LogShowCommand.pagerCommand(environment: ["PAGER": "more"]) == "more")
    #expect(LogShowCommand.pagerCommand(environment: ["PAGER": " "]) == nil)
  }
}
