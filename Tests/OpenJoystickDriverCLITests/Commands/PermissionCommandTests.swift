import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized)
struct PermissionCommandTests {
  private static let inactiveExtension: @Sendable () -> ExtensionStatus = {
    ExtensionStatus(bundle: .present, registration: .absent)
  }

  private static let allGranted = PermissionManager.Snapshot(
    inputMonitoring: .granted,
    accessibility: .granted
  )

  private static let deniedLocally: @Sendable () -> PermissionManager.Snapshot = {
    PermissionManager.Snapshot(inputMonitoring: .denied, accessibility: .granted)
  }

  /// A service that answers `getStatus` with `status` and access requests with `snapshot`,
  /// and records the methods it received.
  private func serve(
    status: (input: String, accessibility: String) = ("granted", "granted"),
    snapshot: PermissionManager.Snapshot = Self.allGranted,
    socketPath: String,
    received: Locked<[String]> = Locked([])
  ) throws -> LocalServiceRPCServer {
    let statusResult = try JSONEncoder().encode(
      try JSONEncoder().encode(
        ApplicationServiceStatusPayload(
          inputMonitoring: status.input,
          accessibility: status.accessibility,
          connectedDevices: []
        )
      )
    )
    let snapshotResult = try JSONEncoder().encode(snapshot)
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { request, completion in
        received.withLock { $0.append(request.method) }
        switch request.method {
        case ApplicationServiceRPCMethod.getStatus.rawValue:
          completion(LocalServiceRPCResponse(result: statusResult, error: nil))
        case ApplicationServiceRPCMethod.requestRequiredAccess.rawValue,
          ApplicationServiceRPCMethod.requestAccess.rawValue:
          completion(LocalServiceRPCResponse(result: snapshotResult, error: nil))
        default:
          completion(LocalServiceRPCResponse(result: nil, error: "unexpected \(request.method)"))
        }
      }
    )
    try server.start()
    return server
  }

  private func run(_ arguments: [String], socketPath: String) async -> CLIRun {
    await ServiceConnection.$socketPath.withValue(socketPath) {
      await StatusCommand.$extensionProbe.withValue(Self.inactiveExtension) {
        await PermissionListCommand.$localSnapshot.withValue(Self.deniedLocally) {
          await CLIRun.run(arguments + ["--timeout", "5"])
        }
      }
    }
  }

  @Test
  func listReadsTheRunningServiceAsJSONAndPlainRows() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(status: ("denied", "granted"), socketPath: socketPath)
    defer { server.stop() }

    let jsonRun = await run(["permission", "list", "--json"], socketPath: socketPath)
    let plainRun = await run(["permission", "list", "--plain"], socketPath: socketPath)

    #expect(jsonRun.code == 0, "\(jsonRun.standardError)")
    #expect(jsonRun.standardError.isEmpty)
    let entries = try #require(try jsonRun.json()["permissions"] as? [[String: String]])
    #expect(entries.map { $0["id"] } == ["input-monitoring", "accessibility", "driver-extension"])
    #expect(entries.map { $0["state"] } == ["denied", "granted", "unknown"])
    #expect(entries[0]["name"] == "Input Monitoring")
    #expect(entries[0]["purpose"] == "Read input from physical controllers")
    #expect(
      plainRun.standardOutput
        == "input-monitoring\tdenied\naccessibility\tgranted\ndriver-extension\tunknown\n"
    )
  }

  @Test
  func listFallsBackToThisProcessWhenTheServiceIsStopped() async throws {
    let result = await run(["permission", "list", "--json"], socketPath: temporarySocketPath())

    #expect(result.code == 0)
    #expect(result.standardError.contains("read by this process"))
    let entries = try #require(try result.json()["permissions"] as? [[String: String]])
    #expect(entries.map { $0["state"] } == ["denied", "granted", "unknown"])
  }

  @Test
  func listPrintsOneHumanRowPerPermission() async {
    let result = await run(["permission", "list"], socketPath: temporarySocketPath())

    let rows = result.standardOutput.split(separator: "\n")
    #expect(rows.count == 3)
    #expect(rows[0].hasPrefix("Input Monitoring"))
    #expect(rows[0].contains("denied"))
    #expect(rows[0].contains("Read input from physical controllers"))
  }

  @Test
  func requestWithoutAServiceExitsWithServiceUnavailable() async {
    let result = await run(["permission", "request"], socketPath: temporarySocketPath())

    #expect(result.code == 69)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.hasPrefix("error["))
    #expect(result.standardError.contains("ojd service start"))
  }

  @Test
  func requestRejectsAnUnknownIdBeforeTheServiceIsAsked() async {
    let result = await run(["permission", "request", "camera"], socketPath: temporarySocketPath())

    #expect(result.code == 64)
    #expect(result.standardError.contains("Unknown permission 'camera'"))
    #expect(result.standardError.contains("input-monitoring, accessibility"))
  }

  @Test
  func requestThatLeavesAPermissionDeniedExitsWith77() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(
      snapshot: .init(inputMonitoring: .denied, accessibility: .granted),
      socketPath: socketPath
    )
    defer { server.stop() }

    let result = await run(["permission", "request", "--no-input"], socketPath: socketPath)

    #expect(result.code == 77)
    #expect(result.standardOutput.contains("Input Monitoring"))
    #expect(result.standardOutput.contains("denied"))
    #expect(
      result.standardError.hasPrefix("error[E2008]: Input Monitoring access is still missing.")
    )
    #expect(result.standardError.contains("System Settings > Privacy & Security >"))
    #expect(result.standardError.contains("Input Monitoring, then"))
    #expect(result.standardError.contains("ojd permission request"))
  }

  @Test
  func requestOnlyJudgesTheRequestedIds() async throws {
    let socketPath = temporarySocketPath()
    let received = Locked<[String]>([])
    let server = try serve(
      snapshot: .init(inputMonitoring: .denied, accessibility: .granted),
      socketPath: socketPath,
      received: received
    )
    defer { server.stop() }

    let result = await run(["permission", "request", "accessibility"], socketPath: socketPath)

    #expect(result.code == 0, "\(result.standardError)")
    #expect(result.standardError == "The requested access is granted.\n")
    #expect(received.withLock { $0 } == [ApplicationServiceRPCMethod.requestAccess.rawValue])
  }

  @Test
  func requestThatGrantsEverythingSucceedsAndPrintsTheStates() async throws {
    let socketPath = temporarySocketPath()
    let received = Locked<[String]>([])
    let server = try serve(socketPath: socketPath, received: received)
    defer { server.stop() }

    let result = await run(["permission", "request", "--json"], socketPath: socketPath)

    #expect(result.code == 0, "\(result.standardError)")
    let entries = try #require(try result.json()["permissions"] as? [[String: String]])
    #expect(entries.map { $0["state"] } == ["granted", "granted", "unknown"])
    let method = ApplicationServiceRPCMethod.requestRequiredAccess.rawValue
    #expect(received.withLock { $0 } == [method])
  }

  @Test
  func permissionMissingNamesThePermissionAndTheRequestCommand() {
    let failure = CLIFailure.permissionMissing("Accessibility")

    #expect(failure.code == .permissionDenied)
    #expect(failure.code.rawValue == 77)
    #expect(
      failure.message == "Accessibility access is missing. Grant it with 'ojd permission request'."
    )
  }
}
