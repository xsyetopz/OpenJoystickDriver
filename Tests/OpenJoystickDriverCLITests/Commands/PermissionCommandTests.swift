import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized, .removingTemporarySockets)
struct PermissionCommandTests {
  private static let inactiveExtension: @Sendable () -> ExtensionStatus = {
    ExtensionStatus(bundle: .present, registration: .absent)
  }

  private static let allGranted = PermissionManager.Snapshot(
    inputRead: .granted,
    inputInject: .granted
  )

  private static let noProfiles = ApplicationServiceRemappingSnapshotPayload(
    profiles: [],
    activeProfiles: [],
    routes: [],
    postEventAccess: .granted
  )

  private static let notAuthorizedLocally: @Sendable () -> RemappingPostEventAccessState = {
    .notAuthorized
  }

  private static let deniedLocally: @Sendable () -> PermissionManager.Snapshot = {
    PermissionManager.Snapshot(inputRead: .denied, inputInject: .granted)
  }

  /// A service that answers `getStatus` with `status` and access requests with `snapshot`,
  /// and records the methods it received.
  private func serve(
    status: (input: PermissionManager.AccessState, inputInject: PermissionManager.AccessState) =
      (.granted, .granted),
    snapshot: PermissionManager.Snapshot = Self.allGranted,
    remapping: ApplicationServiceRemappingSnapshotPayload = Self.noProfiles,
    socketPath: String,
    received: Locked<[String]> = Locked([])
  ) throws -> LocalServiceRPCServer {
    let statusResult = try JSONEncoder().encode(
      try JSONEncoder().encode(
        ApplicationServiceStatusPayload(
          inputRead: status.input,
          inputInject: status.inputInject,
          connectedDevices: []
        )
      )
    )
    let snapshotResult = try JSONEncoder().encode(snapshot)
    let remappingResult = try JSONEncoder().encode(remapping)
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { request in
        received.withLock { $0.append(request.method) }
        switch request.method {
        case ApplicationServiceRPCMethod.getStatus.rawValue:
          return LocalServiceRPCResponse(result: statusResult, error: nil)
        case ApplicationServiceRPCMethod.getRemappingSnapshot.rawValue:
          return LocalServiceRPCResponse(result: remappingResult, error: nil)
        case ApplicationServiceRPCMethod.requestRequiredAccess.rawValue,
          ApplicationServiceRPCMethod.requestAccess.rawValue:
          return LocalServiceRPCResponse(result: snapshotResult, error: nil)
        default:
          return LocalServiceRPCResponse(result: nil, error: "unexpected \(request.method)")
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
          await PermissionListCommand.$localPostEventAccess.withValue(Self.notAuthorizedLocally) {
            await CLIRun.run(arguments + testServerTimeout)
          }
        }
      }
    }
  }

  @Test
  func listReadsRunningServiceAsJSONAndPlainRows() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(status: (.denied, .granted), socketPath: socketPath)
    defer { server.stop() }

    let jsonRun = await run(["permission", "list", "--json"], socketPath: socketPath)
    let plainRun = await run(["permission", "list", "--plain"], socketPath: socketPath)

    #expect(jsonRun.code == 0, "\(jsonRun.standardError)")
    #expect(jsonRun.standardError.isEmpty)
    let entries = try #require(try jsonRun.json()["items"] as? [[String: Any]])
    #expect(
      entries.map { $0["id"] as? String } == [
        "InputRead", "InputInject", "USBTransport", "PostEvent",
      ]
    )
    #expect(
      entries.map { $0["state"] as? String } == ["Denied", "Granted", "Unknown", "Granted"]
    )
    #expect(entries[0]["name"] as? String == "Input read")
    #expect(entries[0]["purpose"] as? String == "Read input from physical controllers")
    #expect(entries[0]["requiredByActiveProfile"] == nil)
    #expect(entries[3]["requiredByActiveProfile"] as? Bool == false)
    #expect(
      plainRun.standardOutput
        == "input-read\tdenied\ninput-inject\tgranted\nusb-transport\tunknown\n"
        + "post-event\tgranted\tnot-required\n"
    )
  }

  @Test
  func listFallsBackToThisProcessWhenServiceIsStopped() async throws {
    let result = await run(["permission", "list", "--json"], socketPath: temporarySocketPath())

    #expect(result.code == 0)
    #expect(!result.standardError.isEmpty)
    let entries = try #require(try result.json()["items"] as? [[String: Any]])
    #expect(entries.map { $0["state"] as? String } == ["Denied", "Granted", "Unknown", "Denied"])
    #expect(entries[3]["requiredByActiveProfile"] == nil)
  }

  @Test
  func listPrintsOneHumanRowPerPermission() async {
    let result = await run(["permission", "list"], socketPath: temporarySocketPath())

    let rows = result.standardOutput.split(separator: "\n")
    #expect(rows.count == 4)
    #expect(rows[0].hasPrefix(PermissionID.inputRead.localizedName))
    #expect(rows[0].contains("denied"))
    #expect(rows[0].hasSuffix(PermissionID.inputRead.localizedPurpose))
  }

  @Test
  func listReportsPostEventAccessNotAuthorizedAndRequiredByActiveProfile() async throws {
    let socketPath = temporarySocketPath()
    let profile = RemappingProfile(
      name: "Keys",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [
        RemappingBinding(source: .button(.south), destination: .keyboard(key: .a, modifiers: []))
      ]
    )
    let remapping = ApplicationServiceRemappingSnapshotPayload(
      profiles: [profile],
      activeProfiles: [
        ApplicationServiceRemappingActiveProfilePayload(
          vendorID: 1,
          productID: 2,
          profileID: profile.id,
          profileName: profile.name,
          applicationScope: .global
        )
      ],
      routes: [],
      postEventAccess: .notAuthorized
    )
    let server = try serve(remapping: remapping, socketPath: socketPath)
    defer { server.stop() }

    let json = await run(["permission", "list", "--json"], socketPath: socketPath)
    let plain = await run(["permission", "list", "--plain"], socketPath: socketPath)
    let human = await run(["permission", "list"], socketPath: socketPath)

    let entries = try #require(try json.json()["items"] as? [[String: Any]])
    #expect(entries[3]["id"] as? String == "PostEvent")
    #expect(entries[3]["state"] as? String == "Denied")
    #expect(entries[3]["requiredByActiveProfile"] as? Bool == true)
    #expect(plain.standardOutput.hasSuffix("post-event\tdenied\trequired\n"))
    let last = try #require(human.standardOutput.split(separator: "\n").last)
    #expect(last.hasPrefix(PermissionID.postEvent.localizedName))
    #expect(last.hasSuffix("(" + CLILocalized.text("cli.permission.group.requiredByProfile") + ")"))
  }

  @Test
  func requestWithoutServiceExitsWithServiceUnavailable() async {
    let result = await run(["permission", "request"], socketPath: temporarySocketPath())

    #expect(result.code == 69)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError == CLIFailure.serviceUnavailable.line + "\n")
  }

  @Test
  func requestRejectsUnknownIdBeforeServiceIsAsked() async {
    let result = await run(["permission", "request", "camera"], socketPath: temporarySocketPath())

    #expect(result.code == 64)
    #expect(result.standardError.contains("camera"))
    #expect(result.standardError.contains("input-read, input-inject"))
  }

  @Test
  func requestThatLeavesPermissionDeniedExitsWith77() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(
      snapshot: .init(inputRead: .denied, inputInject: .granted),
      socketPath: socketPath
    )
    defer { server.stop() }

    let result = await run(["permission", "request", "--no-input"], socketPath: socketPath)

    #expect(result.code == 77)
    #expect(result.standardOutput.contains(PermissionID.inputRead.localizedName))
    #expect(result.standardOutput.contains("denied"))
    #expect(
      result.standardError == CLIFailure.permissionStillMissing([.inputRead]).line + "\n"
    )
    #expect(result.standardError.hasPrefix("error[E2008]: "))
    #expect(result.standardError.contains("ojd permission request"))
  }

  @Test
  func requestOnlyJudgesRequestedIds() async throws {
    let socketPath = temporarySocketPath()
    let received = Locked<[String]>([])
    let server = try serve(
      snapshot: .init(inputRead: .denied, inputInject: .granted),
      socketPath: socketPath,
      received: received
    )
    defer { server.stop() }

    let result = await run(["permission", "request", "input-inject"], socketPath: socketPath)

    #expect(result.code == 0, "\(result.standardError)")
    #expect(result.standardError.split(separator: "\n").count == 1)
    #expect(received.withLock { $0 } == [ApplicationServiceRPCMethod.requestAccess.rawValue])
  }

  @Test
  func requestThatGrantsEverythingSucceedsAndPrintsStates() async throws {
    let socketPath = temporarySocketPath()
    let received = Locked<[String]>([])
    let server = try serve(socketPath: socketPath, received: received)
    defer { server.stop() }

    let result = await run(["permission", "request", "--json"], socketPath: socketPath)

    #expect(result.code == 0, "\(result.standardError)")
    let entries = try #require(try result.json()["permissions"] as? [[String: String]])
    #expect(entries.map { $0["state"] } == ["Granted", "Granted", "Unknown"])
    let method = ApplicationServiceRPCMethod.requestRequiredAccess.rawValue
    #expect(received.withLock { $0 } == [method])
  }

  @Test
  func permissionMissingNamesPermissionAndRequestCommand() {
    let failure = CLIFailure.permissionMissing("Accessibility")

    #expect(failure.code == .permissionDenied)
    #expect(failure.code.rawValue == 77)
    #expect(failure.id == .permissionMissing)
    #expect(failure.message.contains("Accessibility"))
    #expect(failure.message.contains("ojd permission request"))
  }
}
