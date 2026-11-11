import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

struct DocumentMigratorTests {
  private let directory = RootedDataDirectory.temporary()

  private var support: URL { directory.url(for: .applicationData) }

  private func write(_ text: String, _ file: String) throws {
    let url = support.appendingPathComponent(file)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data(text.utf8).write(to: url)
  }

  private func read(_ file: String) throws -> Data {
    try Data(contentsOf: support.appendingPathComponent(file))
  }

  private func exists(_ file: String) -> Bool {
    FileManager.default.fileExists(atPath: support.appendingPathComponent(file).path)
  }

  private func document(_ file: String) throws -> OrderedJSON {
    try OrderedJSON(document: read(file), file: file)
  }

  @Test
  func anAccessGrantsFileBecomesAVersionThreePropertyList() throws {
    try write(MigrationFixtures.accessGrants, "AccessGrants.json")
    let entries = DocumentMigrator(directory: directory).run(dryRun: false)
    #expect(entries.map(\.verdict) == [.migrated])
    #expect(entries.map(\.file) == ["AccessGrants.json"])
    let converted = try document("AccessGrants.plist")
    #expect(converted["apiVersion"]?.string == OpenJoystickDriverAPI.version)
    #expect(converted["enabled"] == .bool(true))
    #expect(!exists("AccessGrants.json"))
  }

  @Test
  func aProfileBecomesAVersionThreePropertyList() throws {
    try write(MigrationFixtures.profile, "Profiles/6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D5E.json")
    let entries = DocumentMigrator(directory: directory).run(dryRun: false)
    #expect(entries.map(\.verdict) == [.migrated], "\(entries)")
    let profile = try RemappingProfileFileStore.load(
      from: support.appendingPathComponent("Profiles/6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D5E.plist")
    )
    #expect(profile.bindings.first?.multiTap.map(\.count) == [2])
  }

  @Test
  func aUserRecordBecomesAVersionThreePropertyList() throws {
    try write(MigrationFixtures.wheelRecord, "Controllers/044f-b671.json")
    let entries = DocumentMigrator(directory: directory).run(dryRun: false)
    #expect(entries.map(\.verdict) == [.migrated])
    let converted = try document("Controllers/044f-b671.plist")
    #expect(converted["apiVersion"]?.string == OpenJoystickDriverAPI.version)
    #expect(converted["productID"] == .number("46705"))
  }

  @Test
  func aPatchGetsBitAddressedLayouts() throws {
    try write(MigrationFixtures.patch, "Controllers/054c-0ce6.patch.json")
    #expect(
      DocumentMigrator(directory: directory).run(dryRun: false).map(\.verdict) == [.migrated]
    )
    let layout = try #require(document("Controllers/054c-0ce6.patch.plist")["patch"]?["input"]?["layouts"])
    #expect(layout.formatted().contains(#""bitOffset": 10"#))
    #expect(layout.formatted().contains(#""bitSize": 16"#))
  }

  private static let badPatch =
    #"{"apiVersion": "openjoystickdriver/v1alpha1", "kind": "ControllerPatch", "#
    + #""selector": {"vendorID": 1, "productID": 2}, "patch": {"input": {"buttons": []}}}"#

  @Test
  func aDryRunListsTheDocumentsAndWritesNothing() throws {
    try write(MigrationFixtures.accessGrants, "AccessGrants.json")
    let entries = DocumentMigrator(directory: directory).run(dryRun: true)
    #expect(entries.map(\.verdict) == [.migrated])
    #expect(exists("AccessGrants.json"))
    #expect(!exists("AccessGrants.plist"))
    #expect(!exists("Migrated"))
  }

  @Test
  func theOriginalIsKeptUnderMigratedWithItsRelativePath() throws {
    try write(MigrationFixtures.profile, "Profiles/6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D5E.json")
    _ = DocumentMigrator(directory: directory).run(dryRun: false)
    #expect(
      try read("Migrated/Profiles/6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D5E.json")
        == Data(MigrationFixtures.profile.utf8)
    )
  }

  @Test
  func anExistingBackupIsNeverOverwrittenAndTheDocumentFails() throws {
    try write(MigrationFixtures.accessGrants, "AccessGrants.json")
    try write("kept", "Migrated/AccessGrants.json")
    let entries = DocumentMigrator(directory: directory).run(dryRun: false)
    #expect(entries.map(\.verdict) == [.failed])
    #expect(try read("Migrated/AccessGrants.json") == Data("kept".utf8))
    #expect(exists("AccessGrants.json"))
    #expect(!exists("AccessGrants.plist"))
  }

  @Test
  func oneFailureDoesNotStopTheOthers() throws {
    try write(Self.badPatch, "Controllers/bad.patch.json")
    try write(MigrationFixtures.accessGrants, "AccessGrants.json")
    let entries = DocumentMigrator(directory: directory).run(dryRun: false)
    #expect(
      entries.map(\.verdict) == [.migrated, .failed],
      "\(entries)"
    )
    #expect(exists("AccessGrants.plist"))
    #expect(exists("Controllers/bad.patch.json"))
    #expect(!exists("Migrated/Controllers/bad.patch.json"))
  }

  @Test
  func aSecondRunFindsTheMigratedDocumentCurrent() throws {
    try write(MigrationFixtures.accessGrants, "AccessGrants.json")
    _ = DocumentMigrator(directory: directory).run(dryRun: false)
    let entries = DocumentMigrator(directory: directory).run(dryRun: false)
    #expect(entries.map(\.verdict) == [.current])
    #expect(entries.map(\.file) == ["AccessGrants.plist"])
  }

  @Test
  func aJSONFileBesideItsPropertyListFailsAndKeepsBoth() throws {
    try write(MigrationFixtures.accessGrants, "AccessGrants.json")
    try write("existing", "AccessGrants.plist")
    let entries = DocumentMigrator(directory: directory).run(dryRun: false)
    #expect(entries.map(\.verdict).contains(.failed))
    #expect(try read("AccessGrants.plist") == Data("existing".utf8))
    #expect(exists("AccessGrants.json"))
  }

  @Test
  func aFileOfAnotherProgramIsForeignAndUntouched() throws {
    try write(#"{"name": "mine"}"#, "Profiles/notes.json")
    try write("not json", "Controllers/readme.json")
    let entries = DocumentMigrator(directory: directory).run(dryRun: false)
    #expect(entries.map(\.verdict) == [.foreign, .foreign])
    #expect(exists("Profiles/notes.json"))
  }

  @Test
  func aZeroFiveDocumentFailsWithAReason() throws {
    try write(#"{"$schema": "x", "profiles": []}"#, "RemappingProfiles.json")
    let entries = DocumentMigrator(directory: directory).run(dryRun: false)
    #expect(entries.map(\.verdict) == [.failed])
    #expect(entries.first?.detail == "written by 0.5; re-create it")
    #expect(exists("RemappingProfiles.json"))
    #expect(!exists("Migrated"))
  }

  @Test
  func theActiveProfilesArrayBecomesAPropertyList() throws {
    try write(
      #"[{"profileID": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D5E", "vendorID": 1, "productID": 2}]"#,
      "ActiveProfiles.json"
    )
    let entries = DocumentMigrator(directory: directory).run(dryRun: false)
    #expect(entries.map(\.verdict) == [.migrated], "\(entries)")
    guard case .array(let items) = try document("ActiveProfiles.plist") else {
      Issue.record("not an array")
      return
    }
    #expect(items.count == 1)
  }

  @Test
  func anActiveProfilesScopeKeepsItsAppsAsAList() throws {
    try write(
      #"""
      [{"profileID": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D5E", "vendorID": 1, "productID": 2,
        "applicationScope": {"type": "Application", "appID": "com.example.game"}}]
      """#,
      "ActiveProfiles.json"
    )
    let entries = DocumentMigrator(directory: directory).run(dryRun: false)
    #expect(entries.map(\.verdict) == [.migrated], "\(entries)")
    guard case .array(let items) = try document("ActiveProfiles.plist") else {
      Issue.record("not an array")
      return
    }
    let scope = try #require(items.first?["applicationScope"])
    #expect(scope["appIDs"] == .array([.string("com.example.game")]))
    #expect(scope["appID"] == nil)
  }

  @Test
  func aFolderArgumentIsScannedRecursivelyWithItsOwnBackups() throws {
    try write(MigrationFixtures.accessGrants, "Elsewhere/Sub/AccessGrants.json")
    let folder = support.appendingPathComponent("Elsewhere")
    let entries = DocumentMigrator(directory: directory).run(dryRun: false, folder: folder)
    #expect(entries.map(\.file) == ["Sub/AccessGrants.json"])
    #expect(exists("Elsewhere/Sub/AccessGrants.plist"))
    #expect(exists("Elsewhere/Migrated/Sub/AccessGrants.json"))
  }

  @Test
  func packagesAreScannedBelowTheirFolder() throws {
    try write(
      MigrationFixtures.document(MigrationFixtures.alphaOne, "ModPackage", #""name": "x""#),
      "Packages/x/mod.json"
    )
    let entries = DocumentMigrator(directory: directory).run(dryRun: true)
    #expect(entries.map(\.file) == ["Packages/x/mod.json"])
  }
}
