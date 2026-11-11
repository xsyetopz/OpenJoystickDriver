import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

@Suite
struct PauseShortcutTests {
  private let root = RootedDataDirectory.temporary()

  private var store: SettingsStore { SettingsStore(directory: root) }

  @Test
  func aFreshInstallationHasNoShortcut() throws {
    #expect(try store.pauseShortcut() == nil)
    #expect(try store.load().pauseShortcut == nil)
  }

  @Test
  func textParsesAndPrintsInTheSameForm() throws {
    let shortcut = try PauseShortcut(parsing: "Control+Option+P")
    #expect(shortcut.key == "P")
    #expect(shortcut.modifiers == [.control, .option])
    #expect(shortcut.text == "Control+Option+P")
    #expect(try PauseShortcut(parsing: shortcut.text) == shortcut)
    #expect(try PauseShortcut(parsing: "shift+command+f12").text == "Command+Shift+F12")
  }

  @Test
  func keyCodesAreTheAnsiVirtualKeyCodes() throws {
    #expect(try PauseShortcut(parsing: "command+A").keyCode == 0x00)
    #expect(try PauseShortcut(parsing: "command+P").keyCode == 0x23)
    #expect(try PauseShortcut(parsing: "command+Space").keyCode == 0x31)
    #expect(try PauseShortcut(parsing: "command+F12").keyCode == 0x6F)
    for name in PauseShortcut.keyNames {
      let code = try PauseShortcut(key: name, modifiers: [.command]).keyCode
      #expect(PauseShortcut.keyName(code: code) == name)
    }
    #expect(PauseShortcut.keyName(code: 0xFF) == nil)
  }

  @Test(arguments: ["", "P", "shift+P", "command+", "command+Home", "command+control", "hyper+P"])
  func textThatIsNotAShortcutIsRefused(text: String) {
    #expect(throws: PauseShortcutError.self) { try PauseShortcut(parsing: text) }
  }

  @Test
  func theStoreWritesAndClearsTheShortcut() throws {
    let shortcut = try PauseShortcut(parsing: "control+option+P")
    try store.setPauseShortcut(shortcut)
    #expect(try store.pauseShortcut() == shortcut)

    let object = try PropertyListFixture.dictionary(at: store.userFileURL)
    let stored = try #require(object["pauseShortcut"] as? [String: Any])
    #expect(stored["key"] as? String == "P")
    #expect(stored["modifiers"] as? [String] == ["Control", "Option"])

    try store.setPauseShortcut(nil)
    #expect(try store.pauseShortcut() == nil)
    let cleared = try PropertyListFixture.dictionary(at: store.userFileURL)
    #expect(cleared["pauseShortcut"] == nil)
  }

  @Test
  func aShortcutDoesNotDisturbTheOtherSettings() throws {
    try store.set(.developerTools, to: true)
    try store.setPauseShortcut(try PauseShortcut(parsing: "command+shift+P"))
    try store.set(.notifySounds, to: false)

    #expect(try store.value(of: .developerTools))
    #expect(try store.value(of: .notifySounds) == false)
    #expect(try store.pauseShortcut()?.text == "Command+Shift+P")
  }

  @Test(arguments: [
    #""pauseShortcut": {"key": "P", "modifiers": []}"#,
    #""pauseShortcut": {"key": "P", "modifiers": ["Shift"]}"#,
    #""pauseShortcut": {"key": "P", "modifiers": ["Command", "Command"]}"#,
    #""pauseShortcut": {"key": "P", "modifiers": ["command"]}"#,
    #""pauseShortcut": {"key": "Home", "modifiers": ["Command"]}"#,
    #""pauseShortcut": {"key": "P"}"#,
    #""pauseShortcut": {"key": "P", "modifiers": ["Command"], "extra": true}"#,
    #""pauseShortcut": "command+P""#,
  ])
  func aFileWithAnInvalidShortcutIsDamaged(body: String) throws {
    let url = store.userFileURL
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try PropertyListFixture.bytes(
      json: #"{"apiVersion": "\#(OpenJoystickDriverAPI.version)", "kind": "Settings", \#(body)}"#
    ).write(to: url)

    #expect(throws: SettingsStoreError.damaged(file: url.path)) { try store.load() }
  }

  @Test
  func theKeyNamesAreTheSchemaEnumeration() throws {
    let schema = try JSONSchemaFiles.document(named: "settings.schema.json")
    let properties = try #require(schema["properties"] as? [String: Any])
    let shortcut = try #require(properties["pauseShortcut"] as? [String: Any])
    let shortcutProperties = try #require(shortcut["properties"] as? [String: Any])
    let key = try #require(shortcutProperties["key"] as? [String: Any])
    let modifiers = try #require(shortcutProperties["modifiers"] as? [String: Any])
    let items = try #require(modifiers["items"] as? [String: Any])

    #expect(key["enum"] as? [String] == PauseShortcut.keyNames)
    #expect(items["enum"] as? [String] == PauseShortcut.Modifier.allCases.map(\.rawValue))
  }
}
