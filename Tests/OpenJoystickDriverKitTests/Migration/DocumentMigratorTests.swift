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
    #expect(entries.map(\.status) == [.converted])
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
    #expect(entries.map(\.status) == [.converted], "\(entries)")
    let profile = try RemappingProfileFileStore.load(
      from: support.appendingPathComponent("Profiles/6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D5E.plist")
    )
    #expect(profile.bindings.first?.multiTap.map(\.count) == [2])
  }

  @Test
  func aUserRecordBecomesAVersionThreePropertyList() throws {
    try write(MigrationFixtures.wheelRecord, "Controllers/044f-b671.json")
    let entries = DocumentMigrator(directory: directory).run(dryRun: false)
    #expect(entries.map(\.status) == [.converted])
    let converted = try document("Controllers/044f-b671.plist")
    #expect(converted["apiVersion"]?.string == OpenJoystickDriverAPI.version)
    #expect(converted["productID"] == .number("46705"))
  }

  @Test
  func aPatchGetsBitAddressedLayouts() throws {
    try write(MigrationFixtures.patch, "Controllers/054c-0ce6.patch.json")
    #expect(
      DocumentMigrator(directory: directory).run(dryRun: false).map(\.status) == [.converted]
    )
    let layout = try #require(document("Controllers/054c-0ce6.patch.plist")["patch"]?["input"]?["layouts"])
    #expect(layout.formatted().contains(#""bitOffset": 10"#))
    #expect(layout.formatted().contains(#""bitSize": 16"#))
  }
}
