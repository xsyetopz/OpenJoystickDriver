import Foundation
import Testing

struct PhysicalOutputParityTests {
  @Test
  func cliGuiStatusAndSupportReportExposeTypedPhysicalOutput() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let cli = try source("Sources/OpenJoystickDriver/CLI.swift", root: root)
    let command = try source(
      "Sources/OpenJoystickDriver/Commands/PhysicalOutputCommand.swift",
      root: root
    )
    let appModel = try source(
      "Sources/OpenJoystickDriver/App/AppModel+XPCOperations.swift",
      root: root
    )
    let view = try source(
      "Sources/OpenJoystickDriver/Views/InputTestWindowView+Rumble.swift",
      root: root
    )
    let status = try source(
      "Sources/OpenJoystickDriver/Commands/StatusCommand.swift",
      root: root
    )
    let protocolSource = try source(
      "Sources/OpenJoystickDriverKit/XPC/XPCProtocol.swift",
      root: root
    )
    let client = try source(
      "Sources/OpenJoystickDriverKit/XPC/XPCClient.swift",
      root: root
    )
    let service = try source(
      "Sources/OpenJoystickDriverDaemon/XPCService+Protocol.swift",
      root: root
    )
    let report = try source(
      "Sources/OpenJoystickDriverKit/Diagnostics/SupportReport.swift",
      root: root
    )

    #expect(cli.contains("case \"physical-output\""))
    #expect(command.contains("sendPhysicalRumble"))
    #expect(command.contains("setPhysicalPlayerIndicator"))
    #expect(command.contains("physicalOutputCapabilities"))
    #expect(command.contains("capabilities.evidence.rawValue"))
    #expect(command.contains("capabilities.binaryRumbleMotors"))
    #expect(command.contains(#"case "brightness""#))
    #expect(command.contains(#"case "color""#))
    #expect(command.contains(#"case "plan""#))
    #expect(command.contains("supportsProgrammableBrightness"))
    #expect(appModel.contains("setPhysicalPlayerIndicator"))
    #expect(view.contains("physicalOutputCapabilities"))
    #expect(view.contains("capabilities.evidence.rawValue"))
    #expect(view.contains("capabilities.binaryRumbleMotors"))
    #expect(view.contains("supportsProgrammableBrightness"))
    #expect(view.contains("sendPhysicalBrightness"))
    #expect(view.contains("sendPhysicalColor"))
    #expect(view.contains("PhysicalOutputValidationPlan"))
    #expect(view.contains("showPhysicalOutputValidationPlan"))
    #expect(appModel.contains("setPhysicalBrightness"))
    #expect(appModel.contains("setPhysicalColor"))
    #expect(protocolSource.contains("setPhysicalBrightness"))
    #expect(protocolSource.contains("setPhysicalColor"))
    #expect(client.contains("setPhysicalBrightness"))
    #expect(client.contains("setPhysicalColor"))
    #expect(service.contains("setPhysicalBrightness"))
    #expect(service.contains("setPhysicalColor"))
    #expect(view.contains("supportsTriggerRumble"))
    #expect(view.contains("sendPlayerIndicator"))
    #expect(status.contains("physical-output motors="))
    #expect(status.contains("physicalOutputCapabilities.evidence.rawValue"))
    #expect(report.contains("physicalOutputCapabilities"))
    #expect(report.contains("outputValidationPlans"))
  }

  private func source(_ path: String, root: URL) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }
}
