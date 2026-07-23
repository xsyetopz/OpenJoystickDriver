import Foundation
import Testing

struct UpdateAndLogParityTests {
  @Test func headlessUpdateCheckUsesTheSharedChecker() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let cli = try source("Sources/OpenJoystickDriver/CLIGrammar.swift", root: root)
    let command = try source("Sources/OpenJoystickDriver/Commands/UpdatesCommand.swift", root: root)
    let checker = try source("Sources/OpenJoystickDriverKit/Update/UpdateChecker.swift", root: root)

    #expect(cli.contains("case \"update\""))
    #expect(command.contains("UpdateChecker().check"))
    #expect(command.contains("--prerelease"))
    #expect(command.contains("--json"))
    #expect(command.contains("--open"))
    #expect(command.contains("checks GitHub tags"))
    #expect(command.contains("latestTag: latestTag"))
    #expect(checker.contains("request.timeoutInterval = Self.requestTimeoutSeconds"))
    #expect(checker.contains("/repos/xsyetopz/OpenJoystickDriver/tags"))
    #expect(!checker.contains("/releases"))
  }

  @Test func headlessLogsUseTypedServiceLogPaths() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let cli = try source("Sources/OpenJoystickDriver/CLIGrammar.swift", root: root)
    let command = try source("Sources/OpenJoystickDriver/Commands/LogsCommand.swift", root: root)
    let service = try source(
      "Sources/OpenJoystickDriverKit/Diagnostics/ApplicationServiceLogService.swift",
      root: root
    )

    #expect(cli.contains("case \"logs\""))
    #expect(command.contains("ApplicationServiceLogService.tail"))
    #expect(command.contains("ApplicationServiceLogService.url"))
    #expect(command.contains("ApplicationServiceLogService.sharingWarning"))
    #expect(command.contains("--lines"))
    #expect(command.contains("--json"))
    #expect(service.contains("defaultMaximumBytes = 262_144"))
  }

  private func source(_ path: String, root: URL) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }
}
