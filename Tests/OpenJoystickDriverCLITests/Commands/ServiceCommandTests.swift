import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized)
struct ServiceCommandTests {
  private let stoppedExtension: @Sendable () -> ExtensionStatus = {
    ExtensionStatus(bundle: .present, registration: .absent)
  }

  /// A user record directory that holds no records, so `ojd status` never reads the real one.
  private static func emptyRecordDirectory() -> URL {
    URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
  }

  /// Runs `ojd status` with the extension stopped and `records` as the user record directory.
  private func runStatus(
    _ arguments: [String],
    socketPath: String = temporarySocketPath(),
    records: URL = Self.emptyRecordDirectory()
  ) async -> CLIRun {
    await RecordStore.$directory.withValue(records) {
      await ServiceConnection.$socketPath.withValue(socketPath) {
        await StatusCommand.$extensionProbe.withValue(stoppedExtension) {
          await CLIRun.run(["status"] + arguments)
        }
      }
    }
  }

  @Test
  func statusReportsAStoppedServiceAsStateAndExitsZero() async throws {
    let result = await runStatus(["--json"])
    #expect(result.code == 0)
    let json = try result.json()
    let service = try #require(json["service"] as? [String: Any])
    #expect(service["state"] as? String == "stopped")
    let extensionState = try #require(json["extension"] as? [String: Any])
    #expect(extensionState["bundle"] as? String == "present")
    #expect(extensionState["registration"] as? String == "absent")
    #expect(json["controllers"] == nil)
    #expect((json["skippedRecords"] as? [Any])?.isEmpty == true)
  }

  @Test
  func statusNamesTheSkippedRecordsOfTheInjectedDirectoryOnly() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-status-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("{".utf8).write(to: directory.appendingPathComponent("broken.json"))

    let withFile = await runStatus(["--plain"], records: directory)
    let withoutFile = await runStatus(["--plain"])

    #expect(withFile.code == 0, "\(withFile.standardError)")
    #expect(withFile.standardOutput.contains("skipped-record\t"))
    #expect(withFile.standardOutput.contains("/broken.json\t"))
    #expect(!withoutFile.standardOutput.contains("skipped-record"))
  }

  @Test
  func statusNamesAnIgnoredDefaultsFileAndSkippedPersonaFiles() async throws {
    let support = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-status-\(UUID().uuidString)",
      isDirectory: true
    )
    let personas = support.appendingPathComponent("Personas", isDirectory: true)
    try FileManager.default.createDirectory(
      at: support.appendingPathComponent("Controllers"),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(at: personas, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: support) }
    try Data("{".utf8).write(to: support.appendingPathComponent("Defaults.json"))
    try Data("{".utf8).write(to: personas.appendingPathComponent("broken.json"))

    let json = await runStatus(["--json"], records: support.appendingPathComponent("Controllers"))
    let plain = await runStatus(["--plain"], records: support.appendingPathComponent("Controllers"))
    let clean = await runStatus(["--json"])

    let report = try json.json()
    let defaults = try #require(report["ignoredDefaults"] as? [String: String])
    #expect(defaults["file"]?.hasSuffix("/Defaults.json") == true)
    #expect(defaults["problem"] == "the file is not a JSON object")
    let skipped = try #require(report["skippedPersonas"] as? [[String: String]])
    #expect(skipped.map { $0["file"]?.hasSuffix("/Personas/broken.json") } == [true])
    #expect(plain.standardOutput.contains("ignored-defaults\t"))
    #expect(plain.standardOutput.contains("skipped-persona\t"))
    let cleanReport = try clean.json()
    #expect(cleanReport["ignoredDefaults"] == nil)
    #expect((cleanReport["skippedPersonas"] as? [Any])?.isEmpty == true)
  }

  @Test
  func statusReportsTheRunningServiceInJSONAndPlainRows() async throws {
    let socketPath = temporarySocketPath()
    let payload = ApplicationServiceStatusPayload(
      inputMonitoring: "granted",
      accessibility: "denied",
      connectedDevices: [
        ApplicationServiceDeviceDescription(
          name: "Test Pad",
          vendorID: 0x045E,
          productID: 0x028E,
          protocolBinding: ProtocolBindingID(.hidDescriptor),
          connection: "USB",
          discoverySource: .rawUSB,
          serialNumber: nil,
          bindingResult: .hidDescriptorFixture,
          runtimeIdentifier: "pad-1"
        )
      ],
      userSpaceVirtualDeviceEnabled: true
    )
    let result = try JSONEncoder().encode(try JSONEncoder().encode(payload))
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { request, completion in
        let isStatus = request.method == ApplicationServiceRPCMethod.getStatus.rawValue
        completion(
          LocalServiceRPCResponse(
            result: isStatus ? result : nil,
            error: isStatus ? nil : "unexpected \(request.method)"
          )
        )
      }
    )
    try server.start()
    defer { server.stop() }

    let jsonRun = await runStatus(["--json", "--timeout", "5"], socketPath: socketPath)
    let plainRun = await runStatus(["--plain", "--timeout", "5"], socketPath: socketPath)

    #expect(jsonRun.code == 0, "\(jsonRun.standardError)")
    let json = try jsonRun.json()
    let service = try #require(json["service"] as? [String: Any])
    #expect(service["state"] as? String == "running")
    let permissions = try #require(json["permissions"] as? [String: Any])
    #expect(permissions["inputMonitoring"] as? String == "granted")
    #expect(permissions["accessibility"] as? String == "denied")
    let controllers = try #require(json["controllers"] as? [[String: Any]])
    #expect(controllers.count == 1)
    #expect(controllers.first?["id"] as? String == "pad-1")
    #expect(controllers.first?["vendorID"] as? Int == 0x045E)

    #expect(plainRun.code == 0, "\(plainRun.standardError)")
    let rows = plainRun.standardOutput.split(separator: "\n").map {
      $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    }
    #expect(rows.first?.prefix(2) == ["service", "running"])
    #expect(rows.contains(["permission", "accessibility", "denied"]))
    #expect(rows.contains(["controller", "pad-1", "045E:028E", "USB", "Test Pad"]))
  }

  @Test(arguments: ["start", "wait"])
  func startAndWaitReportARunningService(verb: String) async throws {
    let service = try FakeService(devices: [])
    let result = await service.run(["service", verb, "--json"])
    #expect(result.code == 0, "\(result.standardError)")
    #expect(try result.json()["state"] as? String == "running")
  }

  @Test
  func waitWithoutAServiceExitsSixtyNineAfterTheTimeout() async {
    let result = await ServiceConnection.$socketPath.withValue(temporarySocketPath()) {
      await CLIRun.run(["service", "wait", "--timeout", "0.2"])
    }
    #expect(result.code == 69)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.hasPrefix("error[E2004]: "))
    #expect(result.standardError.contains("ojd service start"))
  }

  @Test
  func stopWithoutAServiceReportsStopped() async throws {
    let result = await ServiceConnection.$socketPath.withValue(temporarySocketPath()) {
      await CLIRun.run(["service", "stop", "--json"])
    }
    #expect(result.code == 0)
    #expect(try result.json()["state"] as? String == "stopped")
  }

  @Test
  func quietSuppressesTheSuccessMessage() async {
    let path = temporarySocketPath()
    let loud = await ServiceConnection.$socketPath.withValue(path) {
      await CLIRun.run(["service", "stop"])
    }
    let quiet = await ServiceConnection.$socketPath.withValue(path) {
      await CLIRun.run(["service", "stop", "--quiet"])
    }
    #expect(loud.code == 0 && quiet.code == 0)
    #expect(!loud.standardError.isEmpty)
    #expect(loud.standardOutput.isEmpty)
    #expect(quiet.standardError.isEmpty && quiet.standardOutput.isEmpty)
  }

  @Test
  func applicationBundleFollowsTheInstalledLink() {
    let executable = URL(
      fileURLWithPath: "/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver"
    )
    #expect(
      ServiceStartCommand.applicationBundleURL(executableURL: executable)?.path
        == "/Applications/OpenJoystickDriver.app"
    )
    #expect(
      ServiceStartCommand.applicationBundleURL(
        executableURL: URL(fileURLWithPath: "/repo/.build/debug/OpenJoystickDriver")
      ) == nil
    )
  }
}
