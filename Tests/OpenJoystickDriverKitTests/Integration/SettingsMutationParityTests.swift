import Foundation
import Testing

struct SettingsMutationParityTests {
  @Test func headlessResetRemainsAvailableWithoutObsoleteOutputMutations() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let cli = try source("Sources/OpenJoystickDriver/CLIGrammar.swift", root: root)
    let reset = try source(
      "Sources/OpenJoystickDriver/Commands/ResetSettingsCommand.swift",
      root: root
    )
    let requests = try source(
      "Sources/OpenJoystickDriver/Service/ApplicationServiceServer/Requests.swift",
      root: root
    )

    #expect(!cli.contains("case \"userspace\""))
    #expect(cli.contains("case \"output\": return .controllerOutput"))
    #expect(cli.contains("case .reset: ResetSettingsCommand().run()"))
    #expect(reset.contains("client.resetSettings"))

    #expect(requests.contains("public func resetSettings(reply:"))
    #expect(!requests.contains("setUserSpaceVirtualDeviceEnabled"))
    #expect(!requests.contains("setOutputMode"))
  }

  @Test func headlessExtensionRemovalAndPermissionSettingsRemainAvailable() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let cli = try source(
      "Sources/OpenJoystickDriver/Commands/SystemExtensionCommand.swift",
      root: root
    )
    let permissions = try source(
      "Sources/OpenJoystickDriver/Commands/PermissionsCommand.swift",
      root: root
    )

    #expect(cli.contains("case \"disable\""))
    #expect(permissions.contains("case \"open\""))
    #expect(permissions.contains("Open Input Monitoring or Accessibility"))
  }

  private func source(_ path: String, root: URL) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }
}
