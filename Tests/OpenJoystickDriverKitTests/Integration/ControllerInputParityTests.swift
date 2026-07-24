import Foundation
import Testing

struct ControllerInputParityTests {
  @Test
  func cliUsesTheSharedControllerInputDiagnostics() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let cli = try source("Sources/OpenJoystickDriver/CLIGrammar.swift", root: root)
    let command = try source(
      "Sources/OpenJoystickDriver/Commands/InputCommand.swift",
      root: root
    )
    let service = try source(
      "Sources/OpenJoystickDriver/ControllerInputDiagnosticService.swift",
      root: root
    )
    #expect(cli.contains("case \"state\""))
    #expect(cli.contains("InputCommand().run"))
    #expect(command.contains("case \"state\""))
    #expect(command.contains("case \"packets\""))
    #expect(command.contains("case \"watch\""))
    #expect(command.contains("--json-lines"))
    #expect(command.contains("Raw controller packets may contain"))

    #expect(service.contains("client.getStatus()"))
    #expect(service.contains("client.deviceInputState"))
    #expect(service.contains("client.packetLog"))
    #expect(command.contains("ControllerInputDiagnosticService()"))
  }

  private func source(_ path: String, root: URL) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }
}
