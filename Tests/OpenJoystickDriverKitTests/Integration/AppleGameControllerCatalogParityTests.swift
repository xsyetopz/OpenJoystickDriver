import Foundation
import Testing

struct AppleGameControllerCatalogParityTests {
  @Test
  func headlessCommandsUseTheSharedAuditor() throws {
    let root = try RepositoryRoot.from()
    let command = try source(
      "Sources/OpenJoystickDriver/Commands/GameControllerCatalogCommand.swift",
      root: root
    )
    let reportCommand = try source(
      "Sources/OpenJoystickDriver/Commands/ReportCommand.swift",
      root: root
    )
    let supportReport = try source(
      "Sources/OpenJoystickDriverKit/Diagnostics/SupportReport.swift",
      root: root
    )

    #expect(command.contains("AppleGameControllerSupportAuditor"))
    #expect(reportCommand.contains("AppleGameControllerSupportAuditor.auditCurrentSystem()"))
    #expect(!command.contains("Compatibility identity comparison"))
    #expect(!supportReport.contains("AppleGameControllerCompatibilityAudit"))
    #expect(supportReport.contains("appleGameControllerAudit"))

  }

  private func source(_ path: String, root: URL) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }
}
