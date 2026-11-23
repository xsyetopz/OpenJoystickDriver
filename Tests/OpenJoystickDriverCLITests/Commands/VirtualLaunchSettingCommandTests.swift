import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized)
struct VirtualLaunchSettingCommandTests {
  private let root = RootedDataDirectory.temporary()

  private var store: SettingsStore { SettingsStore(directory: root) }

  /// The key `ojd` derives for `/usr/bin/env`.
  private static let envKey = URL(fileURLWithPath: "/usr/bin/env").resolvingSymlinksInPath().path

  private func run(_ arguments: [String]) async -> CLIRun {
    await SettingCatalog.$store.withValue(store) {
      await CLIRun.run(["virtual", "launch-setting"] + arguments)
    }
  }

  private func store(
    _ setting: LaunchSetting,
    for key: String = Self.envKey
  ) throws {
    try store.setLaunchSetting(setting, for: key)
  }

  /// Runs `ojd virtual launch` against the settings file and returns what `env` printed.
  private func launch(_ arguments: [String]) async throws -> (run: CLIRun, printed: String) {
    let service = try FakeService(devices: [
      {
        var device = ApplicationServiceDeviceDescription.fixture(id: "pad-1")
        device.virtualHIDProfile = ApplicationServiceVirtualHIDProfileStatus(
          profile: .generic,
          source: .override,
          override: .generic,
          unavailable: false
        )
        return device
      }()
    ])
    let pipe = Pipe()
    let run = await SettingCatalog.$store.withValue(store) {
      await VirtualLaunchCommand.$baseEnvironment.withValue([
        "PATH": "/usr/bin:/bin", "BASE_ONLY": "base", "SHARED": "base",
      ]) {
        await VirtualLaunchCommand.$programStandardOutput.withValue(pipe.fileHandleForWriting) {
          await service.run(["virtual", "launch"] + arguments + ["/usr/bin/env"])
        }
      }
    }
    try pipe.fileHandleForWriting.close()
    let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
    return (run, try #require(String(bytes: data, encoding: .utf8)))
  }

  @Test
  func setStoresEnvironmentArgumentsAndBackendUnderTheResolvedKey() async throws {
    let result = await run([
      "set", "/usr/bin/env", "--sdl-gamecontroller-backend", "--env", "A=1", "--env", "B=x=y",
      "--argument", "-windowed",
    ])

    #expect(result.code == 0, "\(result.standardError)")
    #expect(
      try store.launchSettings()[Self.envKey]
        == LaunchSetting(
          sdlGameControllerBackend: true,
          environment: ["A": "1", "B": "x=y"],
          arguments: ["-windowed"]
        )
    )
  }

  @Test
  func setRefusesAnInvalidEnvironmentNameWithoutStoring() async throws {
    let result = await run(["set", "/usr/bin/env", "--env", "1BAD=x"])

    #expect(result.code != 0)
    #expect(result.standardError.contains("1BAD"))
    #expect(try store.launchSettings().isEmpty)
  }

  @Test
  func setRefusesAnAssignmentWithoutEquals() async throws {
    let result = await run(["set", "/usr/bin/env", "--env", "NOEQUALS"])

    #expect(result.code != 0)
    #expect(result.standardError.contains("NOEQUALS"))
    #expect(try store.launchSettings().isEmpty)
  }

  @Test
  func showPrintsHumanFormat() async throws {
    try store(
      LaunchSetting(
        sdlGameControllerBackend: true,
        environment: ["B": "2", "A": "1"],
        arguments: ["-x"]
      )
    )
    let result = await run(["show", "/usr/bin/env"])

    #expect(result.code == 0, "\(result.standardError)")
    #expect(
      result.standardOutput == """
        \(Self.envKey)
          sdl-gamecontroller-backend: true
          env: A=1
          env: B=2
          argument: -x

        """
    )
  }

  @Test
  func showPrintsSchemaValidJSON() async throws {
    try store(LaunchSetting(environment: ["A": "1"], arguments: ["-x"]))
    let result = await run(["show", "/usr/bin/env", "--json"])
    let document = try result.json()

    #expect(result.code == 0, "\(result.standardError)")
    #expect(document["program"] as? String == Self.envKey)
    #expect(document["sdlGameControllerBackend"] as? Bool == false)
    #expect(document["environment"] as? [String: String] == ["A": "1"])
    #expect(document["arguments"] as? [String] == ["-x"])
  }

  @Test
  func showPrintsPlainRows() async throws {
    try store(LaunchSetting(environment: ["A": "1"], arguments: ["-x"]))
    let result = await run(["show", "/usr/bin/env", "--plain"])
    let rows = result.standardOutput.split(separator: "\n").map(String.init)

    #expect(result.code == 0, "\(result.standardError)")
    #expect(rows.count == 3)
    #expect(rows.allSatisfy { $0.hasPrefix(Self.envKey) })
    #expect(rows.contains { $0.contains("env") && $0.contains("A=1") })
    #expect(rows.contains { $0.contains("argument") && $0.contains("-x") })
  }

  @Test
  func listPrintsEveryFormatSortedByKey() async throws {
    try store(LaunchSetting(arguments: ["-b"]), for: "org.example.b")
    try store(LaunchSetting(environment: ["A": "1"]), for: "org.example.a")

    let human = await run(["list"])
    let plain = await run(["list", "--plain"])
    let json = await run(["list", "--json"])
    let items = try #require(try json.json()["items"] as? [[String: Any]])

    #expect(human.standardOutput.hasPrefix("org.example.a  "))
    #expect(human.standardOutput.contains("org.example.b  "))
    #expect(plain.standardOutput.split(separator: "\n").count == 2)
    #expect(items.compactMap { $0["program"] as? String } == ["org.example.a", "org.example.b"])
  }

  @Test
  func emptyListIsValidJSONWithNoItems() async throws {
    let json = await run(["list", "--json"])

    #expect(json.code == 0, "\(json.standardError)")
    #expect(try (json.json()["items"] as? [Any])?.isEmpty == true)
  }

  @Test
  func removeDeletesTheSettingAndReportsItInEveryFormat() async throws {
    try store(LaunchSetting(arguments: ["-x"]))
    let json = await run(["remove", "/usr/bin/env", "--json"])

    #expect(json.code == 0, "\(json.standardError)")
    #expect(try json.details()["removed"] as? String == Self.envKey)
    #expect(try store.launchSettings().isEmpty)

    try store(LaunchSetting(arguments: ["-x"]))
    let plain = await run(["remove", "/usr/bin/env", "--plain"])
    #expect(plain.standardOutput == Self.envKey + "\n")
  }

  @Test
  func removeOfAStoredKeyWithNoProgramWorksAndMissingKeyFails() async throws {
    try store(LaunchSetting(arguments: ["-x"]), for: "org.example.gone")
    let removed = await run(["remove", "org.example.gone"])
    let missing = await run(["remove", "org.example.gone"])

    #expect(removed.code == 0, "\(removed.standardError)")
    #expect(missing.code != 0)
  }

  @Test
  func launchAppliesStoredEnvironmentOverBaseAndStoredArgumentsAfterGiven() async throws {
    try store(LaunchSetting(environment: ["SHARED": "stored"], arguments: ["STORED_ARG=1"]))
    let (run, printed) = try await launch([])
    let lines = printed.split(separator: "\n").map(String.init)

    #expect(run.code == 0, "\(run.standardError)")
    #expect(lines.contains("SHARED=stored"))
    #expect(lines.contains("BASE_ONLY=base"))
    #expect(lines.contains("STORED_ARG=1"))
    #expect(!lines.contains { $0.hasPrefix("SDL_JOYSTICK_") })
  }

  @Test
  func launchFlagForcesBackendOverAStoredHintAndNoLaunchSettingsIgnoresStore() async throws {
    try store(LaunchSetting(environment: ["SDL_JOYSTICK_HIDAPI": "1", "SHARED": "stored"]))
    let forced = try await launch(["--sdl-gamecontroller-backend"])
    let ignored = try await launch(["--no-launch-settings"])

    #expect(forced.printed.split(separator: "\n").contains("SDL_JOYSTICK_HIDAPI=0"))
    #expect(ignored.printed.split(separator: "\n").contains("SHARED=base"))
    #expect(!ignored.printed.contains("SDL_JOYSTICK_HIDAPI"))
  }

  @Test
  func storedBackendTurnsTheHintsOnWithoutTheFlag() async throws {
    try store(LaunchSetting(sdlGameControllerBackend: true))
    let (run, printed) = try await launch([])
    let lines = Set(printed.split(separator: "\n").map(String.init))

    #expect(run.code == 0, "\(run.standardError)")
    for (name, value) in SDLLaunchEnvironment.gameControllerBackend {
      #expect(lines.contains("\(name)=\(value)"))
    }
  }
}
