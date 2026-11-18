import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

/// A path under the home folder is `~/…` in human output and absolute in every machine-readable
/// output.
@Suite(.serialized)
struct HomePathOutputTests {
  private static let home = MacOSDataDirectory().url(for: .home).path

  /// A folder name under the home folder that nothing creates.
  private static func unusedFolder(_ name: String) -> URL {
    URL(fileURLWithPath: home, isDirectory: true)
      .appendingPathComponent("ojd-test-\(name)-\(UUID().uuidString)", isDirectory: true)
  }

  private func capture(_ body: () throws -> Void) rethrows -> CLIOutputCapture {
    let capture = CLIOutputCapture()
    try CLIOutput.$capture.withValue(capture) { try body() }
    return capture
  }

  private struct Document: Encodable { let path: String }

  @Test
  func humanTextShowsTildeAndEveryOtherWriteKeepsHomePath() throws {
    let path = "\(Self.home)/Library/x"
    let written = try capture {
      CLIOutput.stdout("out \(path)")
      CLIOutput.stderr("err \(path)")
      CLIOutput.raw(path)
      try CLIOutput.json(Document(path: path), kind: "Test")
      try CLIOutput.jsonLine(Document(path: path), kind: "Test")
      try CLIOutput.jsonLineWithoutEnvelope(Document(path: path))
      CLIOutput.plain([[path]])
    }

    #expect(written.standardError == "err ~/Library/x\n")
    let lines = written.standardOutput.split(separator: "\n", omittingEmptySubsequences: false)
    #expect(lines.first == "out ~/Library/x")
    #expect(lines.dropFirst().first == Substring(path))
    #expect(written.standardOutput.components(separatedBy: path).count == 6)
    #expect(written.standardOutput.components(separatedBy: "~/").count == 2)
  }

  @Test
  func logShowPrintsTildeAndLogPathKeepsAbsoluteFolder() async throws {
    let logs = URL(fileURLWithPath: "\(Self.home)/Library/Logs/OpenJoystickDriver")
    let environment = LogEnvironment(
      directory: { logs },
      tail: { stream, _ in
        ApplicationServiceLogSnapshot(
          stream: stream,
          path: "\(logs.path)/\(stream.rawValue).log",
          exists: true,
          fileSizeBytes: 10,
          lines: ["opened \(logs.path)"],
          truncated: false
        )
      },
      follow: { _, _ in AsyncStream { $0.finish() } },
      page: { _, _ in },
      isTerminal: { false }
    )
    func run(_ arguments: [String]) async -> CLIRun {
      await LogCommand.$environment.withValue(environment) { await CLIRun.run(arguments) }
    }

    let show = await run(["log", "show"])
    let json = await run(["log", "show", "--json"])
    let plain = await run(["log", "show", "--plain"])
    let path = await run(["log", "path"])
    let pathJSON = await run(["log", "path", "--json"])

    #expect(show.standardOutput.contains("== standard-output: ~/Library/Logs/OpenJoystickDriver/"))
    #expect(show.standardOutput.contains("opened ~/Library/Logs/OpenJoystickDriver\n"))
    #expect(!show.standardOutput.contains(Self.home))
    #expect(json.standardOutput.contains(logs.path))
    #expect(plain.standardOutput.contains("opened \(logs.path)"))
    #expect(path.standardOutput == logs.path + "\n")
    #expect(try pathJSON.json()["path"] as? String == logs.path)
  }

  @Test
  func modInstallDryRunPrintsTildeAndJSONAndPlainKeepAbsolutePath() async throws {
    let source = FileManager.default.temporaryDirectory
      .appendingPathComponent("ojd-home-mod-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: source) }
    let controllers = source.appendingPathComponent("Controllers", isDirectory: true)
    try FileManager.default.createDirectory(at: controllers, withIntermediateDirectories: true)
    let record: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": "Controller", "vendorID": 0xFFF1,
      "productID": 1, "modes": [["id": "default", "protocol": ["family": "XboxGIP"]]],
    ]
    try PropertyListFixture.data(tree: record).write(
      to: controllers.appendingPathComponent("fff1-0001.plist")
    )
    let manifest: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ModPackageManifest.kind,
      "name": "arcade-pack", "version": "1.2.3", "author": "Tester",
      "requires": ["minimum": "0.6.0"], "controllers": ["fff1-0001.plist"],
    ]
    try PropertyListFixture.data(tree: manifest).write(
      to: source.appendingPathComponent("mod.plist")
    )
    let packages = Self.unusedFolder("packages")
    let installed = packages.appendingPathComponent("arcade-pack").path

    func run(_ arguments: [String]) async -> CLIRun {
      await ModStore.$directory.withValue(packages) {
        await ModStore.$runningVersion.withValue("0.6.0") {
          await CLIRun.run(["mod", "install", source.path, "--dry-run"] + arguments)
        }
      }
    }
    let human = await run([])
    let json = await run(["--json"])
    let plain = await run(["--plain"])

    #expect(human.code == 0, "\(human.standardError)")
    #expect(human.standardOutput.contains("~/ojd-test-packages-"))
    #expect(!human.standardOutput.contains(Self.home))
    #expect(try json.json()["installed"] as? String == installed)
    #expect(plain.standardOutput == installed + "\n")
  }

  @Test
  func recordInstallDryRunPrintsTildeAndJSONAndPlainKeepAbsolutePath() async throws {
    let patch = PropertyListFixture.bytes(
      json: """
        {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "ControllerPatch",
          "selector": {"vendorID": 13932, "productID": 5},
        "patch": {"tuning": {"stickDeadzone": 0.08}}}
        """
    )
    let records = Self.unusedFolder("records")
    let installed = records.appendingPathComponent("366c-0005.patch.plist").path

    func run(_ arguments: [String]) async -> CLIRun {
      await RecordStore.$directory.withValue(records) {
        await RecordStore.$standardInput.withValue(
          { patch },
          operation: { await CLIRun.run(["record", "install", "-", "--dry-run"] + arguments) }
        )
      }
    }
    let human = await run([])
    let json = await run(["--json"])
    let plain = await run(["--plain"])

    #expect(human.code == 0, "\(human.standardError)")
    #expect(human.standardOutput.contains("~/ojd-test-records-"))
    #expect(!human.standardOutput.contains(Self.home))
    #expect(try json.json()["installed"] as? String == installed)
    #expect(plain.standardOutput == installed + "\n")
  }

  @Test
  func accessListPrintsTildeForClientPathAndJSONKeepsItAbsolute() async throws {
    let program = "\(Self.home)/Applications/Reader.app"
    let identity = CodeSigningIdentity(
      kind: .signed,
      identifier: "com.example.reader",
      publisherID: "ABCDE12345"
    )
    let grant = AccessGrantSummary(
      AccessGrant(
        identity: identity,
        scopes: [.read],
        grantedAt: "2026-10-03T20:00:00Z",
        path: program
      )
    )
    let service = try FakeService(devices: []) { method, _ in
      guard method == .getAccessStatus else { return nil }
      return encoded(
        AccessStatusPayload(
          enabled: true,
          socketPath: "/tmp/endpoint.sock",
          connections: [],
          grants: [grant],
          refused: [],
          web: AccessWebStatus(enabled: false, listening: false, port: nil, pagesPath: "/tmp/p"),
          tokens: [],
          refusedTokens: []
        )
      )
    }

    let human = await service.run(["access", "list"])
    let json = await service.run(["access", "list", "--json"])

    #expect(human.standardOutput.contains("~/Applications/Reader.app"))
    #expect(!human.standardOutput.contains(Self.home))
    #expect(json.standardOutput.contains(program))
  }
}
