import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite
struct SettingInterfaceLevelCommandTests {
  private let root = RootedDataDirectory.temporary()

  private var store: SettingsStore { SettingsStore(directory: root) }

  private func run(_ arguments: [String]) async -> CLIRun {
    await SettingCatalog.$store.withValue(store) {
      await CLIRun.run(["setting"] + arguments)
    }
  }

  @Test
  func levelSimpleOnFreshInstallation() async throws {
    let human = await run(["get", "interfaceLevel"])
    let json = await run(["get", "interfaceLevel", "--json"])

    #expect(human.code == 0, "\(human.standardError)")
    #expect(human.standardOutput == "Simple\n")
    #expect(try json.json()["key"] as? String == "interfaceLevel")
    #expect(try json.json()["value"] as? String == "Simple")
  }

  @Test
  func setStoresLevelAndGetReadsItBack() async throws {
    let set = await run(["set", "interfaceLevel", "Advanced", "--json"])
    let get = await run(["get", "interfaceLevel"])

    #expect(set.code == 0, "\(set.standardError)")
    #expect(try set.json()["value"] as? String == "Advanced")
    #expect(get.standardOutput == "Advanced\n")
    #expect(try store.interfaceLevel() == .advanced)

    let back = await run(["set", "interfaceLevel", "Simple"])
    #expect(back.code == 0, "\(back.standardError)")
    #expect(try store.interfaceLevel() == .simple)
  }

  @Test(arguments: ["Expert", "advanced", "true", ""])
  func valueNotLevelExitsSixtyFourAndChangesNothing(value: String) async throws {
    let result = await run(["set", "interfaceLevel", value])

    #expect(result.code == 64)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.hasPrefix("error[E2003]: "))
    #expect(try store.interfaceLevel() == .simple)
  }
}
