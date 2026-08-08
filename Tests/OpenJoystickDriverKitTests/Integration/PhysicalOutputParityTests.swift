import Foundation
import Testing

struct PhysicalOutputParityTests {
  @Test func cliServiceStatusAndSupportReportExposeTypedPhysicalOutput() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let cli = try source("Sources/OpenJoystickDriver/CLI.swift", root: root)
    let grammar = try source("Sources/OpenJoystickDriver/CLIGrammar.swift", root: root)
    let command = try source(
      "Sources/OpenJoystickDriver/Commands/PhysicalOutputCommand.swift",
      root: root
    )
    let statusText = try source("Sources/OpenJoystickDriver/Status/Text.swift", root: root)
    let client = try source(
      "Sources/OpenJoystickDriverKit/ApplicationService/ApplicationServiceClient.swift",
      root: root
    )
    let service = try source(
      "Sources/OpenJoystickDriver/Service/ApplicationServiceServer/Requests.swift",
      root: root
    )
    let report = try source(
      "Sources/OpenJoystickDriverKit/Diagnostics/SupportReport.swift",
      root: root
    )

    #expect(cli.contains("CLIGrammar"))
    #expect(grammar.contains("case \"controller\""))
    #expect(command.contains("sendPhysicalRumble"))
    #expect(command.contains("setPhysicalPlayerIndicator"))
    #expect(command.contains("physicalOutputCapabilities"))
    #expect(command.contains("capabilities.evidence.rawValue"))
    #expect(command.contains("capabilities.binaryRumbleMotors"))
    #expect(command.contains("id = device.runtimeIdentifier"))
    #expect(command.contains("runtimeIdentifier: device.runtimeIdentifier"))
    #expect(command.contains("ConnectedControllerSelection.resolve"))
    #expect(command.contains(#"case "brightness""#))
    #expect(command.contains(#"case "color""#))
    #expect(command.contains(#"case "plan""#))
    #expect(command.contains("supportsProgrammableBrightness"))
    #expect(client.contains("setPhysicalBrightness"))
    #expect(client.contains("setPhysicalColor"))
    #expect(service.contains("setPhysicalBrightness"))
    #expect(service.contains("setPhysicalColor"))
    #expect(statusText.contains("physical-output motors="))
    #expect(statusText.contains("capabilities.evidence.rawValue"))
    #expect(report.contains("physicalOutputCapabilities"))
    #expect(report.contains("outputValidationPlans"))
  }

  private func source(_ path: String, root: URL) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }
}
