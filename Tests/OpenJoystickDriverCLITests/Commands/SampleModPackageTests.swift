import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverCLI

/// Checks the sample package in `docs/sdk/sample` with the commands a package author runs.
struct SampleModPackageTests {
  /// The repository root, four levels above this file.
  private static let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

  private static let sample = repository.appendingPathComponent("docs/sdk/sample").path

  private static let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures/SampleModPackage")

  /// An application-support folder for one test, with the `Controllers` and `Packages` stores.
  private final class Support {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-sample-\(UUID().uuidString)",
      isDirectory: true
    )

    var controllers: URL { root.appendingPathComponent("Controllers", isDirectory: true) }
    var packages: URL { ModPackageStore.directory(besides: controllers) }

    deinit { try? FileManager.default.removeItem(at: root) }
  }

  private func run(_ arguments: [String], in support: Support) async -> CLIRun {
    await RecordStore.$directory.withValue(support.controllers) {
      await ModStore.$directory.withValue(support.packages) {
        await ModStore.$runningVersion.withValue("0.6.0-alpha.1") {
          await CLIRun.run(arguments)
        }
      }
    }
  }

  @Test
  func modValidateAcceptsTheSample() async throws {
    let support = Support()

    let result = await run(["mod", "validate", Self.sample, "--json"], in: support)

    #expect(result.code == 0, "\(result.standardError)")
    let json = try result.json()
    #expect(json["valid"] as? Bool == true)
    #expect(json["name"] as? String == "ojd-sample")
    #expect(
      json["files"] as? [String] == [
        "Controllers/1209-0001.plist", "Profiles/sample-pad.plist", "VirtualDevices/1209-0001.plist",
      ]
    )
  }

  @Test
  func recordTestReplaysTheSampleRecord() async throws {
    let support = Support()
    let install = await run(["mod", "install", Self.sample, "--json"], in: support)
    #expect(install.code == 0, "\(install.standardError)")

    let result = await run(
      [
        "record", "test", "1209:0001",
        "--packets", Self.fixtures.appendingPathComponent("capture.jsonl").path,
        "--expect", Self.fixtures.appendingPathComponent("expected-state.json").path,
        "--json",
      ],
      in: support
    )

    #expect(result.code == 0, "\(result.standardError)\n\(result.standardOutput)")
    let json = try result.json()
    #expect(json["matches"] as? Bool == true)
    #expect(json["inputReports"] as? Int == 1)
  }
}
