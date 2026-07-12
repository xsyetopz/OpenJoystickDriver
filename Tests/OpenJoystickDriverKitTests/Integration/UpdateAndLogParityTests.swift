import Foundation
import Testing

struct UpdateAndLogParityTests {
  @Test
  func cliAndGuiShareUpdateChecking() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let cli = try source("Sources/OpenJoystickDriver/CLI.swift", root: root)
    let command = try source(
      "Sources/OpenJoystickDriver/Commands/UpdatesCommand.swift",
      root: root
    )
    let appModel = try source(
      "Sources/OpenJoystickDriver/App/AppModel/XPCOperations.swift",
      root: root
    )
    let view = try source(
      "Sources/OpenJoystickDriver/Views/MenuBarPopoverView/DiagnosticCards.swift",
      root: root
    )
    let checker = try source(
      "Sources/OpenJoystickDriverKit/Update/UpdateChecker.swift",
      root: root
    )

    #expect(cli.contains("case \"updates\""))
    #expect(command.contains("UpdateChecker().check"))
    #expect(command.contains("--prerelease"))
    #expect(command.contains("--json"))
    #expect(command.contains("--open"))
    #expect(command.contains("does not download or install"))
    #expect(appModel.contains("updateChecker.check"))
    #expect(appModel.contains("includePrereleases"))
    #expect(view.contains("model.checkForUpdates()"))
    #expect(checker.contains("request.timeoutInterval = Self.requestTimeoutSeconds"))
  }

  @Test
  func cliAndGuiUseTypedDaemonLogPaths() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let cli = try source("Sources/OpenJoystickDriver/CLI.swift", root: root)
    let command = try source(
      "Sources/OpenJoystickDriver/Commands/LogsCommand.swift",
      root: root
    )
    let view = try source(
      "Sources/OpenJoystickDriver/Views/MenuBarPopoverView/DiagnosticCards.swift",
      root: root
    )
    let service = try source(
      "Sources/OpenJoystickDriverKit/Diagnostics/DaemonLogService.swift",
      root: root
    )

    #expect(cli.contains("case \"logs\""))
    #expect(command.contains("DaemonLogService.tail"))
    #expect(command.contains("DaemonLogService.url"))
    #expect(command.contains("DaemonLogService.sharingWarning"))
    #expect(command.contains("--lines"))
    #expect(command.contains("--json"))
    #expect(view.contains("DaemonLogStream.allCases"))
    #expect(view.contains("DaemonLogService.url"))
    #expect(!view.contains("/tmp/com.openjoystickdriver.daemon.out"))
    #expect(service.contains("defaultMaximumBytes = 262_144"))
  }

  private func source(_ path: String, root: URL) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }
}
