import Foundation
import Testing

struct InputMonitoringPromptFlowTests {
  @Test func mainApplicationOwnsRuntimeAndPermissionState() throws {
    let root = try RepositoryRoot.from()
    let delegate = try source(
      "Sources/OpenJoystickDriver/App/AppDelegate.swift",
      root: root
    )
    let runtime = try source(
      "Sources/OpenJoystickDriver/Service/ApplicationServiceRuntime.swift",
      root: root
    )
    let permissionModel = try source(
      "Sources/OpenJoystickDriver/App/AppModel/InputMonitoring.swift",
      root: root
    )

    #expect(delegate.contains("ApplicationServiceRuntime"))
    #expect(runtime.contains("PermissionManager()"))
    #expect(runtime.contains("DeviceManager("))
    #expect(runtime.contains("ApplicationServiceServer("))
    #expect(permissionModel.contains("permissionManager.requestRequiredAccess()"))
    #expect(!permissionModel.contains("client.requestInputMonitoringAccess()"))
    #expect(!permissionModel.contains("LSRegisterURL"))
    #expect(!FileManager.default.fileExists(
      atPath: root.appendingPathComponent("Sources/OpenJoystickDriverDaemon").path
    ))
  }

  @Test func oneApplicationIdentityOwnsBothPermissionStates() throws {
    let root = try RepositoryRoot.from()
    let model = try source(
      "Sources/OpenJoystickDriver/App/AppModel/AppModel.swift",
      root: root
    )
    let view = try source(
      "Sources/OpenJoystickDriver/Views/MenuBarPopoverView/SystemCards.swift",
      root: root
    )
    let permissions = try source(
      "Sources/OpenJoystickDriverKit/Permissions/PermissionManager.swift",
      root: root
    )

    #expect(model.contains("@Published var inputMonitoring"))
    #expect(model.contains("@Published var accessibility"))
    #expect(!model.contains("appInputMonitoring"))
    #expect(!model.contains("InputMonitoringPermissionSnapshot"))
    #expect(view.components(separatedBy: "PermissionRow(").count == 3)
    #expect(!view.contains("permissions.daemonName"))
    #expect(!permissions.contains("OpenJoystickDriver Application service"))
  }

  @Test func commandUsesServiceStatusWithoutResettingTCC() throws {
    let root = try RepositoryRoot.from()
    let command = try source(
      "Sources/OpenJoystickDriver/Commands/PermissionsCommand.swift",
      root: root
    )

    #expect(command.contains("client.getStatus()"))
    #expect(command.contains("running main app"))
    #expect(command.contains("client.requestRequiredAccess()"))
    #expect(!command.contains("tccutil"))
    #expect(!command.contains("--request-input-monitoring"))
  }

  @Test func diagnosticsUseTheRunningApplicationPermissionIdentity() throws {
    let root = try RepositoryRoot.from()
    let command = try source(
      "Sources/OpenJoystickDriver/Commands/DiagnoseCommand.swift",
      root: root
    )

    #expect(command.contains("client.getStatus()"))
    #expect(command.contains("State source     : running main app"))
    #expect(!command.contains("currentInputMonitoringAccessState()"))
    #expect(!command.contains("currentAccessibilityAccessState()"))
  }

  @Test func shutdownSignalsRemainRetained() throws {
    let root = try RepositoryRoot.from()
    let source = try source(
      "Sources/OpenJoystickDriverKit/Device/DeviceManager/Shutdown.swift",
      root: root
    )

    #expect(source.contains("ShutdownSignalSourceStore"))
    #expect(source.contains("private var sources: [DispatchSourceSignal] = []"))
    #expect(source.contains("shutdownSignalSourceStore.retain(sigterm)"))
    #expect(source.contains("shutdownSignalSourceStore.retain(sigint)"))
  }

  private func source(_ path: String, root: URL) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }
}
