import Foundation
import Testing

struct AppleGameControllerCatalogParityTests {
  @Test
  func cliGuiAndReportUseTheSharedAuditor() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let command = try source(
      "Sources/OpenJoystickDriver/Commands/GameControllerCatalogCommand.swift",
      root: root
    )
    let appModel = try source(
      "Sources/OpenJoystickDriver/App/AppModel+AppleGameControllerAudit.swift",
      root: root
    )
    let reportCommand = try source(
      "Sources/OpenJoystickDriver/Commands/ReportCommand.swift",
      root: root
    )
    let view = try source(
      "Sources/OpenJoystickDriver/Views/MenuBarPopoverView+AdvancedCards.swift",
      root: root
    )
    let supportReport = try source(
      "Sources/OpenJoystickDriverKit/Diagnostics/SupportReport.swift",
      root: root
    )

    #expect(command.contains("AppleGameControllerSupportAuditor"))
    #expect(appModel.contains("AppleGameControllerSupportAuditor.auditCurrentSystem()"))
    #expect(reportCommand.contains("AppleGameControllerSupportAuditor.auditCurrentSystem()"))
    #expect(view.contains("model.runAppleGameControllerAudit()"))
    #expect(view.contains("appleBackedCompatibilityProfileCount"))
    #expect(command.contains("audit.compatibilityProfiles"))
    #expect(supportReport.contains("appleGameControllerAudit"))
  }

  private func source(_ path: String, root: URL) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }
}
