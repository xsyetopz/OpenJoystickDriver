import Foundation
import Testing

struct SupportReportParityTests {
  @Test
  func headlessReportCommandUsesTheSharedReportService() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let cli = try String(
      contentsOf: rootURL.appendingPathComponent("Sources/OpenJoystickDriver/CLIGrammar.swift"),
      encoding: .utf8
    )
    let command = try String(
      contentsOf: rootURL.appendingPathComponent(
        "Sources/OpenJoystickDriver/Commands/ReportCommand.swift"
      ),
      encoding: .utf8
    )
    let service = try String(
      contentsOf: rootURL.appendingPathComponent(
        "Sources/OpenJoystickDriver/SupportReportService.swift"
      ),
      encoding: .utf8
    )

    #expect(cli.contains("case \"report\""))
    #expect(command.contains("SupportReportService.make"))
    #expect(command.contains("SupportReportService.write"))
    #expect(service.contains("static func make("))
    #expect(service.contains("static func write("))
  }
}
