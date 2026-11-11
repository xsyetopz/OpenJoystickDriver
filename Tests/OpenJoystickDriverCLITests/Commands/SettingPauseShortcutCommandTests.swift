import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite
struct SettingPauseShortcutCommandTests {
  private let root = RootedDataDirectory.temporary()

  private var store: SettingsStore { SettingsStore(directory: root) }

  private func run(_ arguments: [String]) async -> CLIRun {
    await SettingCatalog.$store.withValue(store) {
      await CLIRun.run(["setting"] + arguments)
    }
  }

  @Test
  func theShortcutIsUnsetOnAFreshInstallation() async throws {
    let human = await run(["get", "pauseShortcut"])
    let json = await run(["get", "pauseShortcut", "--json"])

    #expect(human.code == 0, "\(human.standardError)")
    #expect(human.standardOutput == "none\n")
    #expect(try json.json()["key"] as? String == "pauseShortcut")
    #expect(try json.json()["value"] as? String == "none")
  }

  @Test
  func setStoresTheShortcutAndGetReadsItBack() async throws {
    let set = await run(["set", "pauseShortcut", "Control+Option+P", "--json"])
    let get = await run(["get", "pauseShortcut"])

    #expect(set.code == 0, "\(set.standardError)")
    #expect(try set.json()["value"] as? String == "Control+Option+P")
    #expect(get.standardOutput == "Control+Option+P\n")
    #expect(try store.pauseShortcut()?.text == "Control+Option+P")
  }

  @Test
  func noneClearsTheShortcut() async throws {
    try store.setPauseShortcut(try PauseShortcut(parsing: "command+shift+P"))

    let cleared = await run(["set", "pauseShortcut", "none"])

    #expect(cleared.code == 0, "\(cleared.standardError)")
    #expect(try store.pauseShortcut() == nil)
  }

  @Test(arguments: ["P", "shift+P", "command+Home", "hyper+P", "command+"])
  func aValueThatIsNotAShortcutExitsSixtyFourAndChangesNothing(value: String) async throws {
    let result = await run(["set", "pauseShortcut", value])

    #expect(result.code == 64)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.hasPrefix("error[E2003]: "))
    #expect(try store.pauseShortcut() == nil)
  }
}
