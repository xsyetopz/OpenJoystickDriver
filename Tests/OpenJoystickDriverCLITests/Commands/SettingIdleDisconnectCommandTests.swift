import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite
struct SettingIdleDisconnectCommandTests {
  private let root = RootedDataDirectory.temporary()

  private var store: SettingsStore { SettingsStore(directory: root) }

  private func run(_ arguments: [String]) async -> CLIRun {
    await SettingCatalog.$store.withValue(store) {
      await CLIRun.run(["setting"] + arguments)
    }
  }

  @Test
  func theSettingIsOffOnAFreshInstallation() async throws {
    let human = await run(["get", "idleDisconnectMinutes"])
    let json = await run(["get", "idleDisconnectMinutes", "--json"])

    #expect(human.code == 0, "\(human.standardError)")
    #expect(human.standardOutput == "off\n")
    #expect(try json.json()["key"] as? String == "idleDisconnectMinutes")
    #expect(try json.json()["value"] as? String == "off")
  }

  @Test
  func setStoresTheMinutesAndGetReadsThemBack() async throws {
    let set = await run(["set", "idleDisconnectMinutes", "15"])
    let get = await run(["get", "idleDisconnectMinutes"])

    #expect(set.code == 0, "\(set.standardError)")
    #expect(get.standardOutput == "15\n")
    #expect(try store.idleDisconnectMinutes() == 15)
  }

  @Test
  func offTurnsItOff() async throws {
    try store.setIdleDisconnectMinutes(15)

    let cleared = await run(["set", "idleDisconnectMinutes", "off"])

    #expect(cleared.code == 0, "\(cleared.standardError)")
    #expect(try store.idleDisconnectMinutes() == nil)
  }

  @Test(arguments: ["0", "481", "-5", "soon", "1.5", ""])
  func aValueThatIsNotMinutesExitsSixtyFourAndChangesNothing(value: String) async throws {
    let result = await run(["set", "idleDisconnectMinutes", value])

    #expect(result.code == 64)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.hasPrefix("error[E2003]: "))
    #expect(try store.idleDisconnectMinutes() == nil)
  }
}
