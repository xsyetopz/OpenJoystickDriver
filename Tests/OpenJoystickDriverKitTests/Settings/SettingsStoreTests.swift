import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

@Suite
struct SettingsStoreTests {
  private let root = RootedDataDirectory.temporary()

  private var store: SettingsStore { SettingsStore(directory: root) }

  private func write(_ json: String, to location: DataLocation) throws {
    let url = root.fileURL(SettingsStore.fileName, in: location)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try PropertyListFixture.bytes(json: json).write(to: url)
  }

  private func header(_ body: String = "") -> String {
    #"{"apiVersion": "\#(OpenJoystickDriverAPI.version)", "kind": "Settings"\#(body)}"#
  }

  @Test
  func everySettingRoundTripsThroughUserFile() throws {
    for key in ApplicationSettingKey.allCases {
      for value in [true, false] {
        // Show in menu bar and Show in Dock are never both off.
        if key == .showInMenuBar, !value { try store.set(.showInDock, to: true) }
        if key == .showInDock, !value { try store.set(.showInMenuBar, to: true) }
        try store.set(key, to: value)
        #expect(try store.value(of: key) == value, "\(key.rawValue)")
      }
    }
  }

  @Test(arguments: [
    #", "showInMenuBar": false, "showInDock": false"#, #", "showInMenuBar": false"#,
  ])
  func fileThatTurnsOffEveryEntryPointFailsToLoad(body: String) throws {
    try write(header(body), to: .applicationData)

    #expect(throws: SettingsStoreError.self) { try store.load() }
    do { _ = try store.load() } catch let error as SettingsStoreError {
      guard case .storedNoVisibleEntryPoint(let file) = error else {
        Issue.record("Expected storedNoVisibleEntryPoint, got \(error)")
        return
      }
      #expect(file == store.userFileURL.path)
      #expect(error.localizedDescription.contains("Show in Dock"))
    }
  }

  @Test
  func interfaceLevelSimpleByDefault() throws {
    #expect(try store.interfaceLevel() == .simple)
    try write(header(#", "showInDock": true"#), to: .applicationData)
    #expect(try store.interfaceLevel() == .simple)
  }

  @Test(arguments: InterfaceLevel.allCases)
  func interfaceLevelRoundTripsThroughUserFile(level: InterfaceLevel) throws {
    try store.setInterfaceLevel(level)

    #expect(try store.interfaceLevel() == level)
    #expect(try store.load().interfaceLevel == level)
  }

  @Test
  func interfaceLevelReadFromFileByItsName() throws {
    try write(header(#", "interfaceLevel": "Advanced""#), to: .applicationData)

    #expect(try store.interfaceLevel() == .advanced)
  }

  @Test
  func dockIconIsOffByDefault() throws { #expect(try !store.value(of: .showInDock)) }

  @Test
  func turningOffLastEntryPointFails() throws {
    #expect(throws: SettingsStoreError.noVisibleEntryPoint) {
      try store.set(.showInMenuBar, to: false)
    }
    #expect(try store.value(of: .showInMenuBar))

    try store.set(.showInDock, to: true)
    try store.set(.showInMenuBar, to: false)
    #expect(throws: SettingsStoreError.noVisibleEntryPoint) {
      try store.set(.showInDock, to: false)
    }
    #expect(try store.value(of: .showInDock))
    #expect(throws: SettingsStoreError.noVisibleEntryPoint) {
      try store.update([.showInDock: false, .showInMenuBar: false])
    }
  }

  @Test
  func menuBarItemIsOnAndAutomaticUpdateChecksAreOffByDefault() throws {
    #expect(try store.value(of: .showInMenuBar))
    #expect(try !store.value(of: .updatesCheckAutomatically))
  }

  @Test
  func documentEncodesAndDecodesToItself() throws {
    var document = SettingsDocument()
    for (index, key) in ApplicationSettingKey.allCases.enumerated() {
      document[key] = index.isMultiple(of: 2)
    }

    let decoded = try JSONDecoder().decode(
      SettingsDocument.self,
      from: JSONEncoder().encode(document)
    )

    #expect(decoded == document)
  }

  @Test
  func userFileCarriesHeaderAndDocumentedShape() throws {
    try store.update([.notifySounds: false, .updatesIncludePrereleases: true])

    let object = try PropertyListFixture.dictionary(at: store.userFileURL)
    #expect(object["apiVersion"] as? String == OpenJoystickDriverAPI.version)
    #expect(object["kind"] as? String == "Settings")
    #expect((object["notify"] as? [String: Bool]) == ["sounds": false])
    #expect((object["updates"] as? [String: Bool]) == ["includePrereleases": true])
  }

  @Test
  func missingFilesGiveBuiltInDefaults() throws {
    for key in ApplicationSettingKey.allCases {
      #expect(try store.value(of: key) == key.defaultValue, "\(key.rawValue)")
    }
  }

  @Test
  func userFileOverridesBuiltInDefaults() throws {
    try write(
      header(
        #", "notify": {"sounds": false, "controllerConnected": true}, "developerTools": true"#
      ),
      to: .applicationData
    )

    #expect(try store.value(of: .notifySounds) == false)
    #expect(try store.value(of: .developerTools) == true)
    #expect(try store.value(of: .notifyControllerConnected) == true)
    #expect(try store.value(of: .notifyProfileActivated) == false)
  }

  @Test
  func twoStoresWritingDifferentKeysAtOnceLoseNoUpdate() async throws {
    // Show in menu bar stays on: the entry-point guard refuses the all-false rounds.
    let keys = ApplicationSettingKey.allCases.filter {
      $0 != .launchAtLogin && $0 != .showInMenuBar
    }
    let first = store
    let second = store
    for round in 0..<20 {
      let value = round.isMultiple(of: 2)
      try await withThrowingTaskGroup(of: Void.self) { group in
        for (index, key) in keys.enumerated() {
          let writer = index.isMultiple(of: 2) ? first : second
          group.addTask { try writer.set(key, to: value) }
        }
        try await group.waitForAll()
      }
      for key in keys {
        #expect(try store.value(of: key) == value, "round \(round) \(key.rawValue)")
      }
    }
  }

  @Test
  func launchAtLoginIsStoredAsItsOpposite() throws {
    try store.set(.launchAtLogin, to: false)

    #expect(try store.launchAtLoginOptOut())
    let object = try PropertyListFixture.dictionary(at: store.userFileURL)
    #expect(object["launchAtLoginOptOut"] as? Bool == true)
    try store.set(.launchAtLogin, to: true)
    #expect(try store.launchAtLoginOptOut() == false)
  }

  @Test(arguments: [
    #"{"kind": "Settings"}"#,
    #"{"apiVersion": "openjoystickdriver/v0", "kind": "Settings"}"#,
    #"{"apiVersion": "openjoystickdriver/v1alpha1", "kind": "Settings"}"#,
    #"{"apiVersion": "openjoystickdriver/v1alpha2", "kind": "Settings"}"#,
  ])
  func missingOrUnsupportedAPIVersionIsE5001NamingFile(json: String) throws {
    try write(json, to: .applicationData)

    do {
      _ = try store.load()
      Issue.record("the file was accepted")
    } catch let SettingsStoreError.unsupported(_, problem) {
      #expect(problem.code == .unsupportedAPIVersion)
      #expect(problem.description.hasPrefix("E5001: "))
      #expect(problem.description.contains(store.userFileURL.path))
      if json.contains("v1alpha2") {
        #expect(problem.description.contains("openjoystickdriver/v1alpha2"))
      }
      if json.contains("apiVersion") {
        #expect(problem.description.contains("ojd migrate"))
      }
    }
  }

  @Test
  func wrongKindIsRejectedWithoutCode() throws {
    try write(
      #"{"apiVersion": "\#(OpenJoystickDriverAPI.version)", "kind": "Profile"}"#,
      to: .applicationData
    )

    do {
      _ = try store.load()
      Issue.record("the file was accepted")
    } catch let SettingsStoreError.unsupported(_, problem) {
      #expect(problem.code == nil)
      #expect(problem.description.contains("expected Settings, found Profile"))
    }
  }

  @Test(arguments: [
    "not a property list",
    #"{"apiVersion": "openjoystickdriver/v1alpha3", "kind": "Settings", "mystery": true}"#,
    #"{"apiVersion": "openjoystickdriver/v1alpha3", "kind": "Settings", "notify": {"mystery": 1}}"#,
    #"{"apiVersion": "openjoystickdriver/v1alpha3", "kind": "Settings", "developerTools": "yes"}"#,
    #"{"apiVersion": "openjoystickdriver/v1alpha3", "kind": "Settings", "interfaceLevel": "Pro"}"#,
    #"{"apiVersion": "openjoystickdriver/v1alpha3", "kind": "Settings", "interfaceLevel": 1}"#,
  ])
  func damagedFileIsErrorNotEmptyLayer(json: String) throws {
    try write(json, to: .applicationData)

    #expect(throws: SettingsStoreError.damaged(file: store.userFileURL.path)) {
      _ = try store.load()
    }
    #expect(throws: SettingsStoreError.self) { try store.set(.developerTools, to: true) }
  }

  /// A store whose Trash is a folder in the test's own root.
  private var trashingStore: (store: SettingsStore, trash: URL) {
    let trash = root.url(for: .applicationData).appendingPathComponent("Trash")
    let store = SettingsStore(directory: root) { url in
      try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
      try FileManager.default.moveItem(
        at: url,
        to: trash.appendingPathComponent(url.lastPathComponent)
      )
    }
    return (store, trash)
  }

  @Test
  func moveToTrashMakesRejectedFileUsableAgain() throws {
    try write(header(#", "showInMenuBar": false"#), to: .applicationData)
    let (store, trash) = trashingStore
    #expect(throws: SettingsStoreError.self) { try store.load() }

    #expect(try store.moveToTrash())

    #expect(!FileManager.default.fileExists(atPath: store.userFileURL.path))
    #expect(
      FileManager.default.fileExists(
        atPath: trash.appendingPathComponent(SettingsStore.fileName).path
      )
    )
    #expect(
      try store.value(of: .showInMenuBar) == ApplicationSettingKey.showInMenuBar.defaultValue
    )
    try store.set(.developerTools, to: true)
    #expect(try store.value(of: .developerTools))
  }

  @Test
  func moveToTrashWithoutFileMovesNothing() throws {
    let (store, trash) = trashingStore

    #expect(try !store.moveToTrash())
    #expect(!FileManager.default.fileExists(atPath: trash.path))
  }

  @Test
  func fileThatCannotBeTrashedIsReportedNotIgnored() throws {
    try write(header(#", "showInMenuBar": false"#), to: .applicationData)
    let store = SettingsStore(directory: root) { _ in throw CocoaError(.fileWriteNoPermission) }

    #expect(throws: SettingsStoreError.cannotReset(file: store.userFileURL.path)) {
      try store.moveToTrash()
    }
    #expect(FileManager.default.fileExists(atPath: store.userFileURL.path))
  }

  @Test
  func everyErrorIsLocalizedAndNamesRecovery() throws {
    let file = "/tmp/Settings.plist"
    let errors: [SettingsStoreError] = [
      .damaged(file: file), .unwritable(file: file), .cannotReset(file: file),
      .storedNoVisibleEntryPoint(file: file), .noVisibleEntryPoint,
    ]
    for error in errors {
      let text = try #require(error.errorDescription)
      #expect(!text.contains("ui.settings.advanced.error"), "\(error) renders its raw key")
      #expect(error.file == (error == .noVisibleEntryPoint ? nil : file))
    }
    for error in errors where error.fileIsUnusable {
      #expect(try #require(error.errorDescription).contains("ojd setting reset"))
    }
  }
}
