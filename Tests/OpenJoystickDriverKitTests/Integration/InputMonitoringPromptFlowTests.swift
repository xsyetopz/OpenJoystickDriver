import Foundation
import Testing

struct InputMonitoringPromptFlowTests {
  @Test func headlessApplicationHostOwnsRuntimeAndPermissionState() throws {
    let root = try RepositoryRoot.from()
    let host = try source(
      "Sources/OpenJoystickDriver/App/HeadlessApplicationHost.swift",
      root: root
    )
    let runtime = try source(
      "Sources/OpenJoystickDriver/Service/ApplicationServiceRuntime.swift",
      root: root
    )
    let requests = try source(
      "Sources/OpenJoystickDriver/Service/ApplicationServiceServer/Requests.swift",
      root: root
    )

    #expect(host.contains("private let runtime = ApplicationServiceRuntime()"))
    #expect(host.contains("runtime.start()"))
    #expect(runtime.contains("PermissionManager()"))
    #expect(runtime.contains("DeviceManager("))
    #expect(runtime.contains("ApplicationServiceServer("))
    #expect(requests.contains("requestRequiredAccess(reply:"))
    #expect(!requests.contains("tccutil"))
    #expect(!FileManager.default.fileExists(
      atPath: root.appendingPathComponent("Sources/OpenJoystickDriverDaemon").path
    ))
  }

  @Test func runningServiceOwnsBothPermissionStates() throws {
    let root = try RepositoryRoot.from()
    let requests = try source(
      "Sources/OpenJoystickDriver/Service/ApplicationServiceServer/Requests.swift",
      root: root
    )
    let client = try source(
      "Sources/OpenJoystickDriverKit/ApplicationService/ApplicationServiceClient.swift",
      root: root
    )
    let permissions = try source(
      "Sources/OpenJoystickDriverKit/Permissions/PermissionManager.swift",
      root: root
    )

    #expect(requests.contains("let permissions = await pm.refreshAccessState()"))
    #expect(requests.contains("inputMonitoring: \""))
    #expect(requests.contains("accessibility: \""))
    #expect(requests.contains("requestRequiredAccess(reply:"))
    #expect(client.contains("public func getStatus()"))
    #expect(client.contains("public func requestRequiredAccess()"))
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
