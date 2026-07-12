import Foundation
import Testing

struct ControllerInputParityTests {
  @Test
  func cliAndGuiShareControllerInputDiagnostics() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let cli = try source("Sources/OpenJoystickDriver/CLI.swift", root: root)
    let command = try source(
      "Sources/OpenJoystickDriver/Commands/InputCommand.swift",
      root: root
    )
    let service = try source(
      "Sources/OpenJoystickDriver/ControllerInputDiagnosticService.swift",
      root: root
    )
    let view = try source(
      "Sources/OpenJoystickDriver/Views/InputTestWindowView/InputTestWindowView.swift",
      root: root
    )

    #expect(cli.contains("case \"input\""))
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
    #expect(view.contains("ControllerInputDiagnosticService()"))
    #expect(!view.contains("private actor InputTestSampler"))
  }

  @Test
  func diagnosticWindowSamplesAtDisplayCadence() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let view = try source(
      "Sources/OpenJoystickDriver/Views/InputTestWindowView/InputTestWindowView.swift",
      root: root
    )

    #expect(view.contains("inputRefreshIntervalNanoseconds: UInt64 = 16_666_667"))
    #expect(!view.contains("inputRefreshIntervalNanoseconds: UInt64 = 8_333_333"))
  }

  private func source(_ path: String, root: URL) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }
}
