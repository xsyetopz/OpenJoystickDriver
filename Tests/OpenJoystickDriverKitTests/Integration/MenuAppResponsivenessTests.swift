import Foundation
import Testing

struct MenuAppResponsivenessTests {
  @Test
  func applicationAndCLISubprocessesAreAsyncAndBounded() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let polling = try source(
      "Sources/OpenJoystickDriver/App/AppModel/Polling.swift",
      root: root
    )
    let inputMonitoring = try source(
      "Sources/OpenJoystickDriver/App/AppModel/InputMonitoring.swift",
      root: root
    )
    let browserService = try source(
      "Sources/OpenJoystickDriver/Commands/BrowserGamepadDiagnosticService.swift",
      root: root
    )
    let systemExtension = try source(
      "Sources/OpenJoystickDriver/App/SystemExtensionManager.swift",
      root: root
    )
    let permissionManager = try source(
      "Sources/OpenJoystickDriverKit/Permissions/PermissionManager.swift",
      root: root
    )

    #expect(polling.contains("ensureBundleSignatureValid(for action: String) async"))
    #expect(polling.contains("Task.detached(priority: .userInitiated)"))
    #expect(polling.contains("BoundedProcessRunner.run"))
    #expect(!polling.contains("waitUntilExit()"))

    #expect(inputMonitoring.contains("permissionManager.requestRequiredAccess()"))
    #expect(!inputMonitoring.contains("BoundedProcessRunner"))
    #expect(!inputMonitoring.contains("tccutil"))
    #expect(permissionManager.contains("public func refreshAccessState()"))

    #expect(browserService.contains("Task.detached(priority: .userInitiated)"))
    #expect(browserService.contains("BoundedProcessRunner.run"))
    #expect(!browserService.contains("waitUntilExit()"))

    #expect(systemExtension.contains("await Self.isSysextActiveAsync"))
    #expect(systemExtension.contains("BoundedProcessRunner.run"))
    #expect(!systemExtension.contains("waitUntilExit()"))
  }

  @Test
  func cliAndServiceUseTheSameBoundedProcessPrimitive() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let cliUtilities = try source(
      "Sources/OpenJoystickDriver/CLIUtilities.swift",
      root: root
    )
    let serviceManager = try source(
      "Sources/OpenJoystickDriverKit/ApplicationService/ApplicationServiceManager.swift",
      root: root
    )
    let permissions = try source(
      "Sources/OpenJoystickDriver/Commands/PermissionsCommand.swift",
      root: root
    )
    let systemExtension = try source(
      "Sources/OpenJoystickDriver/Commands/SystemExtensionCommand.swift",
      root: root
    )

    for content in [cliUtilities, serviceManager, systemExtension] {
      #expect(content.contains("BoundedProcessRunner.run"))
    }
    #expect(!cliUtilities.contains("waitUntilExit()"))
    #expect(!serviceManager.contains("waitUntilExit()"))
    #expect(!permissions.contains("waitUntilExit()"))
    #expect(!systemExtension.contains("waitUntilExit()"))
  }

  private func source(_ path: String, root: URL) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }
}
