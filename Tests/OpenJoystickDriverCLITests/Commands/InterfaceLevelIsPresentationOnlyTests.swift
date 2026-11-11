import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

/// The interface level only changes what the app shows: the service never reads it and `ojd`
/// prints the same for both values.
@Suite(.serialized, .removingTemporarySockets)
struct InterfaceLevelIsPresentationOnlyTests {
  /// The source folders that make up the service: its target and the two it depends on besides the
  /// kit, which owns the setting.
  private static let serviceFolders = [
    "OpenJoystickDriverService", "OpenJoystickDriverMacOSPlatform", "OpenJoystickDriverUSB",
  ]

  private static var sources: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent()  // Commands
      .deletingLastPathComponent()  // OpenJoystickDriverCLITests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // repository
      .appendingPathComponent("Sources", isDirectory: true)
  }

  @Test(arguments: serviceFolders)
  func theServiceReadsNoInterfaceLevel(folder: String) throws {
    let root = Self.sources.appendingPathComponent(folder, isDirectory: true)
    let files = try #require(
      FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
    ).compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    #expect(!files.isEmpty, "no sources found under \(root.path)")

    for file in files {
      let text = try String(contentsOf: file, encoding: .utf8)
      #expect(
        !text.lowercased().contains("interfacelevel"),
        "\(folder)/\(file.lastPathComponent) mentions the interface level"
      )
    }
  }

  /// A service that answers `getSettings` with the defaults.
  private func serve(socketPath: String) throws -> LocalServiceRPCServer {
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { request in
        guard request.method == ApplicationServiceRPCMethod.getSettings.rawValue else {
          return LocalServiceRPCResponse(result: nil, error: "unexpected \(request.method)")
        }
        let values = ApplicationSettingKey.allCases.map {
          ApplicationSettingValue(key: $0, value: $0.defaultValue)
        }
        return LocalServiceRPCResponse(
          result: try? JSONEncoder().encode(ApplicationSettingsPayload(settings: values)),
          error: nil
        )
      }
    )
    try server.start()
    return server
  }

  /// Runs each read command with the settings document at `level` and returns what it printed.
  private func outputs(at level: InterfaceLevel, socketPath: String) async throws -> [CLIRun] {
    let store = SettingsStore(directory: RootedDataDirectory.temporary())
    try store.setInterfaceLevel(level)
    let commands = [
      ["setting", "list"], ["setting", "list", "--json"], ["setting", "list", "--plain"],
      ["setting", "get", "launchAtLogin"], ["setting", "get", "developerTools", "--json"],
      ["setting", "get", "pauseShortcut"], ["setting", "get", "pauseShortcut", "--json"],
      ["explain", "E2004"], ["explain", "E2004", "--json"],
    ]
    var runs: [CLIRun] = []
    for command in commands {
      runs.append(
        await ServiceConnection.$socketPath.withValue(socketPath) {
          await SettingCatalog.$store.withValue(store) {
            await CLIRun.run(command + testServerTimeout)
          }
        }
      )
    }
    return runs
  }

  @Test
  func ojdPrintsTheSameForBothInterfaceLevels() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(socketPath: socketPath)
    defer { server.stop() }

    let simple = try await outputs(at: .simple, socketPath: socketPath)
    let advanced = try await outputs(at: .advanced, socketPath: socketPath)

    #expect(simple.count == advanced.count)
    for (first, second) in zip(simple, advanced) {
      #expect(first.code == 0, "\(first.standardError)")
      #expect(first.code == second.code)
      #expect(first.standardOutput == second.standardOutput)
      #expect(first.standardError == second.standardError)
    }
    #expect(simple.allSatisfy { !$0.standardOutput.isEmpty })
  }
}
