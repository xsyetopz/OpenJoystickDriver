import Foundation
import Testing

struct AppleGameControllerCatalogParityTests {
  @Test
  func cliAndSupportReportUseSharedAuditorWithoutGUIEntryPoint() throws {
    let root = try RepositoryRoot.from()
    let command = try source(
      "Sources/OpenJoystickDriver/Commands/GameControllerCatalogCommand.swift",
      root: root
    )
    let appSupportReport = try source(
      "Sources/OpenJoystickDriver/App/AppModel/SupportReport.swift",
      root: root
    )
    let appModel = try source(
      "Sources/OpenJoystickDriver/App/AppModel/AppModel.swift",
      root: root
    )
    let reportCommand = try source(
      "Sources/OpenJoystickDriver/Commands/ReportCommand.swift",
      root: root
    )
    let view =
      try source(
        "Sources/OpenJoystickDriver/Views/MenuBarPopoverView/MenuBarPopoverView.swift",
        root: root
      )
      + source(
        "Sources/OpenJoystickDriver/Views/MenuBarPopoverView/DiagnosticCards.swift",
        root: root
      )
    let supportReport = try source(
      "Sources/OpenJoystickDriverKit/Diagnostics/SupportReport.swift",
      root: root
    )

    #expect(command.contains("AppleGameControllerSupportAuditor"))
    #expect(appSupportReport.contains("AppleGameControllerSupportAuditor.auditCurrentSystem()"))
    #expect(reportCommand.contains("AppleGameControllerSupportAuditor.auditCurrentSystem()"))
    #expect(!command.contains("Compatibility identity comparison"))
    #expect(!supportReport.contains("AppleGameControllerCompatibilityAudit"))
    #expect(supportReport.contains("appleGameControllerAudit"))

    for applicationSource in [appModel, view] {
      #expect(!applicationSource.contains("appleGameControllerAuditRunning"))
      #expect(!applicationSource.contains("appleGameControllerCatalogRow"))
      #expect(!applicationSource.contains("appleCatalog."))
    }
    #expect(!FileManager.default.fileExists(
      atPath: root.appendingPathComponent(
        "Sources/OpenJoystickDriver/App/AppModel/AppleGameControllerAudit.swift"
      ).path
    ))
  }

  private func source(_ path: String, root: URL) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }
}
