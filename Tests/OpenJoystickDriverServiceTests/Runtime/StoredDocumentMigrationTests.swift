import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

struct StoredDocumentMigrationTests {
  private let directory = RootedDataDirectory.temporary()

  private func write(_ text: String, _ file: String) throws {
    let url = directory.url(for: .applicationData).appendingPathComponent(file)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data(text.utf8).write(to: url)
  }

  @Test
  func startupConvertsEveryStaleFileAndLogsOneVerdictEach() throws {
    try write(
      #"{"apiVersion": "openjoystickdriver/v1alpha1", "kind": "Settings", "showInDock": true}"#,
      "Settings.json"
    )
    try write(#"{"name": "mine"}"#, "Profiles/notes.json")
    try write(#"{"$schema": "x", "profiles": []}"#, "RemappingProfiles.json")
    nonisolated(unsafe) var lines: [String] = []

    StoredDocumentMigration.run(directory: directory) { lines.append($0) }

    #expect(try SettingsStore(directory: directory).load().showInDock == true)
    #expect(lines.count == 3, "\(lines)")
    #expect(lines.contains("[Migrate] Migrated Settings.json"))
    #expect(lines.contains("[Migrate] Foreign Profiles/notes.json: has no apiVersion"))
    #expect(lines.contains("[Migrate] Failed RemappingProfiles.json: written by 0.5; re-create it"))
  }
}
