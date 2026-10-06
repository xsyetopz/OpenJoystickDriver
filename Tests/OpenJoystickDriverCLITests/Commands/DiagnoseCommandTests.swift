import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized)
struct DiagnoseCommandTests {
  private static let healthyExtension: @Sendable () -> ExtensionStatus = {
    ExtensionStatus(bundle: .present, registration: .active("enabled"))
  }

  private static let noAudit: @Sendable () -> AppleGameControllerSupportAudit? = { nil }

  private static let brokenExtension: @Sendable () -> ExtensionStatus = {
    ExtensionStatus(bundle: .missing, registration: .absent)
  }

  private func serve(socketPath: String) throws -> LocalServiceRPCServer {
    let statusResult = try JSONEncoder().encode(
      try JSONEncoder().encode(
        ApplicationServiceStatusPayload(
          inputMonitoring: "granted",
          accessibility: "granted",
          connectedDevices: [],
          userSpaceVirtualDeviceEnabled: true
        )
      )
    )
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { request, completion in
        if request.method == ApplicationServiceRPCMethod.getStatus.rawValue {
          completion(LocalServiceRPCResponse(result: statusResult, error: nil))
        } else {
          completion(LocalServiceRPCResponse(result: nil, error: "unexpected \(request.method)"))
        }
      }
    )
    try server.start()
    return server
  }

  private func run(
    _ arguments: [String],
    socketPath: String,
    extensionStatus: @escaping @Sendable () -> ExtensionStatus = Self.healthyExtension,
    usb: @escaping @Sendable () async throws -> Int = { 1 },
    records: URL = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
  ) async -> CLIRun {
    await RecordStore.$directory.withValue(records) {
      await runDiagnose(
        arguments,
        socketPath: socketPath,
        extensionStatus: extensionStatus,
        usb: usb
      )
    }
  }

  private func runDiagnose(
    _ arguments: [String],
    socketPath: String,
    extensionStatus: @escaping @Sendable () -> ExtensionStatus,
    usb: @escaping @Sendable () async throws -> Int
  ) async -> CLIRun {
    await ServiceConnection.$socketPath.withValue(socketPath) {
      await StatusCommand.$extensionProbe.withValue(extensionStatus) {
        await DiagnoseCommand.$usbProbe.withValue(usb) {
          await DiagnoseCommand.$gameControllerAudit.withValue(Self.noAudit) {
            await CLIRun.run(["diagnose"] + arguments + ["--timeout", "5"])
          }
        }
      }
    }
  }

  private func statuses(_ run: CLIRun) throws -> [String: String] {
    let checks = try #require(try run.json()["checks"] as? [[String: String]])
    return Dictionary(uniqueKeysWithValues: checks.map { ($0["id"] ?? "", $0["status"] ?? "") })
  }

  @Test
  func everyCheckPassingExitsZeroAndSkipsOnlyTheSoak() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(socketPath: socketPath)
    defer { server.stop() }

    let result = await run(["--json"], socketPath: socketPath)

    #expect(result.code == 0, "\(result.standardError)")
    let statuses = try statuses(result)
    #expect(statuses.filter { $0.value == "skip" }.keys.sorted() == ["runtime-health"])
    #expect(statuses.values.allSatisfy { $0 == "pass" || $0 == "skip" })
    #expect(try result.json()["bundle"] == nil)
  }

  @Test
  func oneFailingCheckExitsOneAndStillPrintsTheTableAndJSON() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(socketPath: socketPath)
    defer { server.stop() }

    let human = await run([], socketPath: socketPath, extensionStatus: Self.brokenExtension)
    let json = await run(["--json"], socketPath: socketPath, extensionStatus: Self.brokenExtension)
    let plain = await run(
      ["--plain"],
      socketPath: socketPath,
      extensionStatus: Self.brokenExtension
    )

    #expect(human.code == 1)
    #expect(human.standardOutput.contains("extension-bundle"))
    #expect(!human.standardError.isEmpty)
    #expect(json.code == 1)
    #expect(try statuses(json)["extension-bundle"] == "fail")
    #expect(plain.code == 1)
    #expect(plain.standardOutput.contains("extension-bundle\tfail\t"))
  }

  @Test
  func aStoppedServiceSkipsItsChecksAndNeverExits69() async throws {
    let result = await run(["--json"], socketPath: temporarySocketPath())

    #expect(result.code == 0, "\(result.standardError)")
    let statuses = try statuses(result)
    for id in ["input-monitoring", "accessibility", "virtual-device", "runtime-health"] {
      #expect(statuses[id] == "skip", "\(id)")
    }
    #expect(statuses["service"] == "warn")
    let checks = try #require(try result.json()["checks"] as? [[String: String]])
    #expect(checks.first { $0["id"] == "accessibility" }?["detail"]?.isEmpty == false)
  }

  @Test
  func aStoppedServiceStillFailsOnAnotherFailingCheck() async throws {
    let result = await run(
      ["--plain"],
      socketPath: temporarySocketPath(),
      extensionStatus: Self.brokenExtension
    )

    #expect(result.code == 1)
    #expect(result.standardOutput.contains("accessibility\tskip\t"))
  }

  @Test
  func aFailingUSBScanWarnsButDoesNotFail() async throws {
    struct ScanError: Error {}
    let failingScan: @Sendable () async throws -> Int = { throw ScanError() }
    let result = await run(["--json"], socketPath: temporarySocketPath(), usb: failingScan)

    #expect(result.code == 0)
    #expect(try statuses(result)["usb-access"] == "warn")
  }

  @Test
  func bundleWritesAFileAndNamesItInJSON() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("support.json").path

    let result = await run(["--bundle", path, "--json"], socketPath: temporarySocketPath())

    #expect(result.code == 0, "\(result.standardError)")
    #expect(try result.json()["bundle"] as? String == path)
    #expect(FileManager.default.fileExists(atPath: path))
    #expect(result.standardError.contains(path))
  }

  @Test
  func aMissingBundleParentIsAUsageError() async {
    let path = "/tmp/\(UUID().uuidString)/missing/support.json"

    let result = await run(["--bundle", path], socketPath: temporarySocketPath())

    #expect(result.code == 64)
    #expect(result.standardOutput.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: path))
  }

  @Test
  func badSoakValuesAreUsageErrors() async {
    let socketPath = temporarySocketPath()
    for arguments in [
      ["--soak", "0"], ["--soak", "86401"], ["--soak", "abc"],
      ["--soak", "5", "--interval-ms", "10"], ["--soak", "5", "--footprint-limit-mib", "-1"],
      ["--soak", "86400", "--interval-ms", "100"],
    ] {
      let result = await run(arguments, socketPath: socketPath)
      #expect(result.code == 64, "\(arguments)")
      #expect(result.standardOutput.isEmpty, "\(arguments)")
    }
  }

  @Test
  func soakAddsARuntimeHealthCheckThatSamplesTheService() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(socketPath: socketPath)
    defer { server.stop() }
    let recorded = Locked<[Int]>([])

    let sampler:
      @Sendable (Int32, Int, Int, RuntimeHealthPolicy) async throws -> RuntimeHealthSummary = {
        _,
        seconds,
        interval,
        _ in
        recorded.withLock { $0 = [seconds, interval] }
        throw RuntimeHealthSamplingError.invalidConfiguration
      }

    let result = await DiagnoseCommand.$soakSampler.withValue(sampler) {
      await run(["--soak", "7", "--interval-ms", "250", "--json"], socketPath: socketPath)
    }

    #expect(recorded.withLock { $0 } == [7, 250])
    #expect(try statuses(result)["runtime-health"] == "fail")
    #expect(result.code == 1)
  }

  @Test
  func aSkippedControllerRecordWarnsButDoesNotFail() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-diagnose-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("{".utf8).write(to: directory.appendingPathComponent("broken.json"))

    let result = await run(["--json"], socketPath: temporarySocketPath(), records: directory)

    #expect(result.code == 0)
    let checks = try #require(try result.json()["checks"] as? [[String: String]])
    let records = try #require(checks.first { $0["id"] == "controller-records" })
    #expect(records["status"] == "warn")
    #expect(records["detail"]?.contains("broken.json (the file is not a JSON object)") == true)
  }
}
