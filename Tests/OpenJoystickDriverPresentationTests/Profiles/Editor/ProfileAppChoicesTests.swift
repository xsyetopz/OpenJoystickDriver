import Foundation
import Testing

@testable import OpenJoystickDriverPresentation

struct ProfileAppChoicesTests {
  private static func app(_ id: String, _ name: String, running: Bool = false) -> ProfileAppChoice {
    ProfileAppChoice(
      bundleID: id,
      name: name,
      url: URL(fileURLWithPath: "/Applications/\(name).app"),
      isRunning: running
    )
  }

  private static func bundle(in directory: URL, name: String, identifier: String?) throws {
    let contents = directory.appendingPathComponent("\(name).app/Contents", isDirectory: true)
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    var plist: [String: Any] = ["CFBundleName": name]
    if let identifier { plist["CFBundleIdentifier"] = identifier }
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
      .write(to: contents.appendingPathComponent("Info.plist"))
  }

  private static func temporaryFolder() throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  @Test
  func runningAppsComeFirstThenInstalledAppsByNameWithoutRepeats() {
    let choices = ProfileAppChoices.merged(
      running: [Self.app("b.Game", "Game", running: true)],
      installed: [
        Self.app("a.Zed", "Zed"), Self.app("b.Game", "Game"), Self.app("a.Alpha", "Alpha"),
      ],
      excluding: []
    )
    #expect(choices.map(\.bundleID) == ["b.Game", "a.Alpha", "a.Zed"])
    #expect(choices.first?.isRunning == true)
  }

  @Test
  func anAppAlreadyInTheProfileIsNotOfferedAgain() {
    let choices = ProfileAppChoices.merged(
      running: [Self.app("a.One", "One", running: true)],
      installed: [Self.app("a.Two", "Two")],
      excluding: ["a.One"]
    )
    #expect(choices.map(\.bundleID) == ["a.Two"])
  }

  @Test
  func anIdentifierOfAnInstalledAppShowsItsName() {
    let entry = ProfileAppChoices.entry(
      for: "a.Two"
    ) { $0 == "a.Two" ? Self.app("a.Two", "Two") : nil }
    #expect(entry.title == "Two")
    #expect(entry.isInstalled)
  }

  @Test
  func anIdentifierOfAnAppThatIsNotInstalledShowsTheIdentifier() {
    let entry = ProfileAppChoices.entry(for: "gone.App") { _ in nil }
    #expect(entry.title == "gone.App")
    #expect(!entry.isInstalled)
  }

  @Test
  func installedAppsAreReadFromTheApplicationFolders() throws {
    let root = try Self.temporaryFolder()
    let utilities = root.appendingPathComponent("Utilities", isDirectory: true)
    try FileManager.default.createDirectory(at: utilities, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Self.bundle(in: root, name: "Racer", identifier: "ex.Racer")
    try Self.bundle(in: utilities, name: "Tool", identifier: "ex.Tool")
    try Self.bundle(in: root, name: "NoID", identifier: nil)

    let found = ProfileAppChoices.installedApps(in: [root])

    #expect(found.map(\.bundleID).sorted() == ["ex.Racer", "ex.Tool"])
    #expect(found.first { $0.bundleID == "ex.Racer" }?.name == "Racer")
  }

  @Test
  func anAppFileGivesItsBundleIdentifier() throws {
    let root = try Self.temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    try Self.bundle(in: root, name: "Racer", identifier: "ex.Racer")

    #expect(
      ProfileAppChoices.choice(forAppAt: root.appendingPathComponent("Racer.app"))?.bundleID
        == "ex.Racer"
    )
    #expect(ProfileAppChoices.choice(forAppAt: root.appendingPathComponent("Missing.app")) == nil)
  }

  @Test
  func theCreationFieldsHoldAListOfApps() {
    var fields = ProfileCreationFields()
    fields.appIDs = ["a.One", "a.Two"]
    #expect(fields.appIDs == ["a.One", "a.Two"])
  }
}
