import Foundation
import Testing

struct SupportReportParityTests {
  @Test
  func cliAndGuiUseTheSameReportService() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let cli = try String(
      contentsOf: rootURL.appendingPathComponent("Sources/OpenJoystickDriver/CLI.swift"),
      encoding: .utf8
    )
    let command = try String(
      contentsOf: rootURL.appendingPathComponent(
        "Sources/OpenJoystickDriver/Commands/ReportCommand.swift"
      ),
      encoding: .utf8
    )
    let appModel = try String(
      contentsOf: rootURL.appendingPathComponent(
        "Sources/OpenJoystickDriver/App/AppModel/SupportReport.swift"
      ),
      encoding: .utf8
    )
    let view = try String(
      contentsOf: rootURL.appendingPathComponent(
        "Sources/OpenJoystickDriver/Views/MenuBarPopoverView/DiagnosticCards.swift"
      ),
      encoding: .utf8
    )

    #expect(cli.contains("case \"report\""))
    #expect(command.contains("SupportReportService.make"))
    #expect(command.contains("SupportReportService.write"))
    #expect(appModel.contains("SupportReportService.make"))
    #expect(appModel.contains("SupportReportService.write"))
    #expect(appModel.contains("NSSavePanel()"))
    #expect(view.contains("model.saveSupportReport()"))
  }
}
