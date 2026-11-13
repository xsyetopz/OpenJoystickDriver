import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized)
struct MigrateCommandTests {
  private let directory = RootedDataDirectory.temporary()

  private func write(_ text: String, _ file: String) throws {
    let url = directory.url(for: .applicationData).appendingPathComponent(file)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data(text.utf8).write(to: url)
  }

  private var support: URL { directory.url(for: .applicationData) }

  private func run(_ arguments: [String]) async -> CLIRun {
    let directory = directory
    return await MigrateCommand.$directory.withValue(directory) {
      await CLIRun.run(["migrate"] + arguments)
    }
  }

  private static let settings =
    #"{"apiVersion": "openjoystickdriver/v1alpha1", "kind": "Settings", "showInDock": true}"#

  @Test
  func dryRunListsDocumentAndChangesNothing() async throws {
    try write(Self.settings, "Settings.json")

    let human = await run(["--dry-run"])
    let json = await run(["--dry-run", "--json"])

    #expect(human.code == 0, "\(human.standardError)")
    #expect(human.standardOutput.contains("Settings.json"))
    #expect(json.code == 0, "\(json.standardError)")
    #expect(json.standardOutput.contains(#""verdict": "Migrated""#))
    #expect(json.standardOutput.contains(#""dryRun": true"#))
    #expect(
      !FileManager.default.fileExists(atPath: support.appendingPathComponent("Settings.plist").path)
    )
    #expect(
      FileManager.default.fileExists(atPath: support.appendingPathComponent("Settings.json").path)
    )
  }

  @Test
  func commandConvertsDocumentSoThatItLoads() async throws {
    try write(Self.settings, "Settings.json")

    let result = await run([])

    #expect(result.code == 0, "\(result.standardError)")
    #expect(try SettingsStore(directory: directory).load().showInDock == true)
    #expect(await run([]).standardOutput.contains("Settings.plist is already current."))
  }

  @Test
  func unconvertibleDocumentFailsWithE5009() async throws {
    try write(
      #"{"apiVersion": "openjoystickdriver/v1alpha1", "kind": "ControllerPatch", "#
        + #""selector": {"vendorID": 1, "productID": 2}, "patch": {"input": {"buttons": []}}}"#,
      "Controllers/bad.patch.json"
    )

    let result = await run([])

    #expect(result.code == 1)
    #expect(result.standardError.contains("error[E5009]"))
    #expect(result.standardOutput.contains("Controllers/bad.patch.json"))
  }

  @Test
  func everyScannedFileGetsVerdictAndForeignFileDoesNotFail() async throws {
    try write(Self.settings, "Settings.json")
    try write(#"{"name": "mine"}"#, "Profiles/notes.json")
    try write(
      #"{"apiVersion": "openjoystickdriver/v1alpha3", "kind": "AccessGrants"}"#,
      "AccessGrants.plist"
    )

    let result = await run(["--plain"])

    #expect(result.code == 0, "\(result.standardError)")
    #expect(result.standardOutput.contains("Migrated\tSettings.json"))
    #expect(result.standardOutput.contains("Foreign\tProfiles/notes.json"))
  }

  @Test
  func folderArgumentScannedInsteadOfSupportFolder() async throws {
    try write(Self.settings, "Settings.json")
    try write(Self.settings, "Other/Settings.json")
    let folder = support.appendingPathComponent("Other").path

    let result = await run([folder])

    #expect(result.code == 0, "\(result.standardError)")
    #expect(
      FileManager.default.fileExists(
        atPath: support.appendingPathComponent("Other/Settings.plist").path
      )
    )
    #expect(
      FileManager.default.fileExists(atPath: support.appendingPathComponent("Settings.json").path)
    )
  }

  @Test
  func zeroFiveFileFailsWithE5009() async throws {
    try write(#"{"$schema": "x", "profiles": []}"#, "RemappingProfiles.json")

    let result = await run([])

    #expect(result.code == 1)
    #expect(result.standardError.contains("error[E5009]"))
    #expect(result.standardOutput.contains("written by 0.5; re-create it"))
  }
}
