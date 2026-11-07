import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

struct DocumentMigratorTests {
  private static let old = "openjoystickdriver/v1alpha1"
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

  private static func document(_ kind: String, _ rest: String) -> String {
    #"{"apiVersion": "\#(old)", "kind": "\#(kind)", \#(rest)}"#
  }

  private static let profile = document(
    "Profile",
    #"""
    "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D5E", "name": "Tap",
    "device": {"vendorID": 1356, "productID": 3302},
    "applicationScope": {"type": "Global"},
    "bindings": [{
      "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D6A",
      "source": {"type": "Button", "button": "East"},
      "destination": {"type": "GamepadButton", "button": "South"},
      "doubleTap": {"windowMs": 250, "destination": {"type": "GamepadButton", "button": "North"}}
    }]
    """#
  )

  private static let patch = document(
    "ControllerPatch",
    #"""
    "selector": {"vendorID": 1356, "productID": 3302},
    "patch": {"input": {"report": {"length": {"atLeast": 2}},
      "buttons": [{"control": "South", "byte": 1, "mask": 12}],
      "axes": [{"control": "LeftStickX", "byte": 2, "bits": 16}]}}
    """#
  )

  @Test
  func aStaleProfileIsConvertedLoadedAndBackedUp() throws {
    try write(Self.profile, "Profiles/a.json")
    let entries = DocumentMigrator(directory: directory).run(dryRun: false)
    #expect(entries.map(\.status) == [.converted])
    #expect(entries.map(\.file) == ["Profiles/a.json"])
    let profile = try JSONDecoder().decode(
      RemappingProfile.self,
      from: read("Profiles/a.json")
    )
    #expect(profile.bindings.first?.multiTap.map(\.count) == [2])
    #expect(String(decoding: try read("Migrated/Profiles/a.json"), as: UTF8.self) == Self.profile)
  }

  @Test
  func aStalePatchGetsBitAddressedLayouts() throws {
    try write(Self.patch, "Controllers/1.patch.json")
    #expect(
      DocumentMigrator(directory: directory).run(dryRun: false).map(\.status) == [.converted]
    )
    let document = try OrderedJSON.parse(read("Controllers/1.patch.json"))
    let layout = try #require(document["patch"]?["input"]?["layouts"])
    #expect(layout.formatted().contains(#""bitOffset": 10"#))
    #expect(layout.formatted().contains(#""bitSize": 2"#))
    #expect(layout.formatted().contains(#""bitOffset": 16"#))
    #expect(layout.formatted().contains(#""bitSize": 16"#))
  }

  @Test
  func aStaleSettingsFileAndVirtualDeviceAreConverted() throws {
    try write(Self.document("Settings", #""showInDock": true"#), "Settings.json")
    try write(
      Self.document(
        "VirtualDevice",
        #""persona": "Generic", "match": {"vendorID": 1, "productID": 2}"#
      ),
      "VirtualDevices/a.json"
    )
    let entries = DocumentMigrator(directory: directory).run(dryRun: false)
    #expect(entries.map(\.status) == [.converted, .converted])
    #expect(try SettingsStore(directory: directory).load().showInDock == true)
    #expect(exists("Migrated/Settings.json"))
  }

  @Test
  func anAccessGrantsFileIsConvertedByVersionOnly() throws {
    try write(Self.document("AccessGrants", #""enabled": true"#), "AccessGrants.json")
    #expect(
      DocumentMigrator(directory: directory).run(dryRun: false).map(\.status) == [.converted]
    )
    let document = try OrderedJSON.parse(read("AccessGrants.json"))
    #expect(document["apiVersion"]?.string == OpenJoystickDriverAPI.version)
  }

  @Test
  func aPatchWithoutAReportStaysUnchangedAndOthersAreConverted() throws {
    let bad = Self.document(
      "ControllerPatch",
      #""selector": {"vendorID": 1, "productID": 2}, "patch": {"input": {"buttons": []}}"#
    )
    try write(bad, "Controllers/bad.patch.json")
    try write(Self.profile, "Profiles/a.json")
    let entries = DocumentMigrator(directory: directory).run(dryRun: false)
    #expect(entries.map(\.status) == [.failed, .converted])
    #expect(entries.first?.detail?.contains("report") == true)
    #expect(String(decoding: try read("Controllers/bad.patch.json"), as: UTF8.self) == bad)
    #expect(!exists("Migrated/Controllers/bad.patch.json"))
  }

  @Test
  func aDryRunListsTheDocumentsAndWritesNothing() throws {
    try write(Self.profile, "Profiles/a.json")
    let entries = DocumentMigrator(directory: directory).run(dryRun: true)
    #expect(entries.map(\.status) == [.wouldConvert])
    #expect(String(decoding: try read("Profiles/a.json"), as: UTF8.self) == Self.profile)
    #expect(!exists("Migrated"))
  }

  @Test
  func currentDocumentsAndOtherFilesAreNotListed() throws {
    let current = Self.profile.replacingOccurrences(
      of: Self.old,
      with: OpenJoystickDriverAPI.version
    )
    try write(current, "Profiles/a.json")
    try write(#"{"active": []}"#, "Profiles/ActiveProfiles.json")
    #expect(DocumentMigrator(directory: directory).run(dryRun: false).isEmpty)
  }

  @Test
  func aSecondRunLeavesTheBackupAndConvertsNothing() throws {
    try write(Self.profile, "Profiles/a.json")
    _ = DocumentMigrator(directory: directory).run(dryRun: false)
    #expect(DocumentMigrator(directory: directory).run(dryRun: false).isEmpty)
  }

  @Test
  func anExistingBackupFailsTheDocumentAndKeepsIt() throws {
    try write(Self.profile, "Profiles/a.json")
    try write("kept", "Migrated/Profiles/a.json")
    let entries = DocumentMigrator(directory: directory).run(dryRun: false)
    #expect(entries.map(\.status) == [.failed])
    #expect(String(decoding: try read("Profiles/a.json"), as: UTF8.self) == Self.profile)
    #expect(String(decoding: try read("Migrated/Profiles/a.json"), as: UTF8.self) == "kept")
  }

  @Test
  func theStepConvertsAControllerRecordInput() throws {
    let input = try OrderedJSON.parse(
      Data(
        (#"{"apiVersion": "\#(Self.old)", "kind": "Controller", "input": {"report": {}, "#
          + #""leftTrigger": {"byte": 5, "button": {"control": "LT", "byte": 6, "mask": 1}}}}"#)
          .utf8
      )
    )
    let converted = try AlphaOneToAlphaTwo.convert(input, kind: .controller).formatted()
    #expect(converted.contains(#""layouts""#))
    #expect(converted.contains(#""bitOffset": 40"#))
    #expect(converted.contains(#""bitOffset": 48"#))
  }
}
