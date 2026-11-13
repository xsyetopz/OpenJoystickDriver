import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite
struct SettingResetCommandTests {
  private let root = RootedDataDirectory.temporary()
  private let trash = FileManager.default.temporaryDirectory.appendingPathComponent(
    "ojd-setting-reset-trash-\(UUID().uuidString)"
  )

  /// A store whose Trash is a folder of its own, so no test touches the user's Trash.
  private var store: SettingsStore {
    let trash = trash
    return SettingsStore(directory: root) { url in
      try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
      try FileManager.default.moveItem(
        at: url,
        to: trash.appendingPathComponent(url.lastPathComponent)
      )
    }
  }

  private func writeRejectedFile() throws {
    try FileManager.default.createDirectory(
      at: store.folderURL,
      withIntermediateDirectories: true
    )
    try Data(
      (#"{"apiVersion": "\#(OpenJoystickDriverAPI.version)", "kind": "Settings", "#
        + #""showInMenuBar": false}"#).utf8
    ).write(to: store.userFileURL)
  }

  private func run(_ arguments: [String]) async -> CLIRun {
    await SettingResetCommand.$store.withValue(store) {
      await CLIRun.run(["setting", "reset"] + arguments)
    }
  }

  @Test
  func forceMovesRejectedFileToTrash() async throws {
    try writeRejectedFile()

    let result = await run(["--force", "--json"])

    #expect(result.code == 0, "\(result.standardError)")
    let details = try #require(try result.json()["details"] as? [String: Any])
    #expect(details["moved"] as? Bool == true)
    #expect(details["file"] as? String == store.userFileURL.path)
    #expect(!FileManager.default.fileExists(atPath: store.userFileURL.path))
    #expect(
      FileManager.default.fileExists(
        atPath: trash.appendingPathComponent(SettingsStore.fileName).path
      )
    )
    #expect(try store.value(of: .showInMenuBar) == ApplicationSettingKey.showInMenuBar.defaultValue)
  }

  @Test
  func withoutForceUnattendedRunAsksForConfirmationAndKeepsFile() async throws {
    try writeRejectedFile()

    let result = await run([])

    #expect(result.code != 0)
    #expect(result.standardError.contains("--force"))
    #expect(FileManager.default.fileExists(atPath: store.userFileURL.path))
  }

  @Test
  func withoutFileNothingMovesAndNoConfirmationIsNeeded() async throws {
    let human = await run([])
    let json = await run(["--json"])

    #expect(human.code == 0, "\(human.standardError)")
    #expect(human.standardOutput.contains(store.userFileURL.path))
    let details = try #require(try json.json()["details"] as? [String: Any])
    #expect(details["moved"] as? Bool == false)
    #expect(!FileManager.default.fileExists(atPath: trash.path))
  }
}
