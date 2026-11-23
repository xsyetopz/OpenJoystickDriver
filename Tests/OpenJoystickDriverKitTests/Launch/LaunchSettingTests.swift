import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

@Suite
struct LaunchSettingTests {
  private let root = RootedDataDirectory.temporary()

  private var store: SettingsStore { SettingsStore(directory: root) }

  /// Writes an `.app` bundle with `identifier` into a fresh folder and returns it.
  private func makeApp(identifier: String) throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    let app = folder.appendingPathComponent("Game.app", isDirectory: true)
    let macOS = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
    try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
    let info: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundleExecutable": "game"]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
      .write(to: app.appendingPathComponent("Contents/Info.plist"))
    let executable = macOS.appendingPathComponent("game")
    try Data("#!/bin/sh\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    return app
  }

  @Test
  func appAndItsInnerExecutableShareOneKey() throws {
    let app = try makeApp(identifier: "org.example.game")
    let inner = app.appendingPathComponent("Contents/MacOS/game")

    #expect(try LaunchSettingKey.key(for: app.path, searchPath: nil) == "org.example.game")
    #expect(try LaunchSettingKey.key(for: inner.path, searchPath: nil) == "org.example.game")
    #expect(LaunchSettingKey.key(forExecutable: inner) == "org.example.game")
  }

  @Test
  func steamStyleInnerPathInsideNestedFoldersResolvesToTheBundle() throws {
    let app = try makeApp(identifier: "org.example.steam")
    let nested = app.appendingPathComponent("Contents/MacOS/Helpers", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    let helper = nested.appendingPathComponent("helper")
    try Data().write(to: helper)

    #expect(LaunchSettingKey.key(forExecutable: helper) == "org.example.steam")
  }

  @Test
  func bareExecutableIsKeyedByItsResolvedPath() throws {
    let key = try LaunchSettingKey.key(for: "/bin/sh", searchPath: nil)

    #expect(key == URL(fileURLWithPath: "/bin/sh").resolvingSymlinksInPath().path)
    #expect(key.hasPrefix("/"))
  }

  @Test
  func bareNameIsFoundOnTheSearchPath() throws {
    let key = try LaunchSettingKey.key(for: "env", searchPath: "/usr/bin")

    #expect(key == URL(fileURLWithPath: "/usr/bin/env").resolvingSymlinksInPath().path)
  }

  @Test(arguments: ["PATH", "_x", "SDL_VIDEO_DRIVER", "a1"])
  func validEnvironmentNamesPass(_ name: String) throws {
    #expect(LaunchSetting.isValidEnvironmentName(name))
    try LaunchSetting(environment: [name: "1"]).validate()
  }

  @Test(arguments: ["", "1A", "A-B", "A B", "A=B", "é"])
  func invalidEnvironmentNamesFailWithNamedError(_ name: String) {
    #expect(!LaunchSetting.isValidEnvironmentName(name))
    #expect(throws: LaunchSettingError.invalidEnvironmentName(name)) {
      try LaunchSetting(environment: [name: "1"]).validate()
    }
  }

  @Test
  func assignmentSplitsAtTheFirstEquals() throws {
    let parsed = try LaunchSetting.assignment("A=b=c")

    #expect(parsed.name == "A")
    #expect(parsed.value == "b=c")
    #expect(throws: LaunchSettingError.invalidEnvironmentAssignment("NOEQUALS")) {
      try LaunchSetting.assignment("NOEQUALS")
    }
    #expect(throws: LaunchSettingError.invalidEnvironmentName("1A")) {
      try LaunchSetting.assignment("1A=x")
    }
  }

  @Test
  func storedEnvironmentOverridesBaseThenSDLMappingFollowsStoredConfig() throws {
    let setting = LaunchSetting(environment: [
      "KEEP": "stored", SDLLaunchEnvironment.variable: "0000,custom,a:b0",
    ])
    let environment = try setting.launchEnvironment(
      adding: [.generic],
      over: ["KEEP": "base", "OTHER": "base", SDLLaunchEnvironment.variable: "base-mapping"],
      gameControllerBackend: false
    )
    let mapping = try VirtualHIDProfileID.generic.gamepadMapping().sdlMapping

    #expect(environment["KEEP"] == "stored")
    #expect(environment["OTHER"] == "base")
    #expect(environment[SDLLaunchEnvironment.variable] == "0000,custom,a:b0\n" + mapping)
    #expect(!environment.keys.contains { $0.hasPrefix("SDL_JOYSTICK_") })
  }

  @Test
  func backendFlagForcesTheHintsOverStoredValuesAndStoredFlag() throws {
    let stored = LaunchSetting(environment: ["SDL_JOYSTICK_HIDAPI": "1"])
    let forced = try stored.launchEnvironment(
      adding: [.generic],
      over: [:],
      gameControllerBackend: true
    )
    let fromStore = try LaunchSetting(sdlGameControllerBackend: true).launchEnvironment(
      adding: [.generic],
      over: [:],
      gameControllerBackend: false
    )

    #expect(forced["SDL_JOYSTICK_HIDAPI"] == "0")
    for (name, value) in SDLLaunchEnvironment.gameControllerBackend {
      #expect(forced[name] == value)
      #expect(fromStore[name] == value)
    }
  }

  @Test
  func storedArgumentsFollowGivenArguments() {
    let setting = LaunchSetting(arguments: ["-windowed"])

    #expect(setting.launchArguments(after: ["--level", "2"]) == ["--level", "2", "-windowed"])
  }

  @Test
  func storeRoundTripsAndRemovesASetting() throws {
    let setting = LaunchSetting(
      sdlGameControllerBackend: true,
      environment: ["A": "1"],
      arguments: ["-x"]
    )
    try store.setLaunchSetting(setting, for: "org.example.game")

    #expect(try store.launchSettings() == ["org.example.game": setting])
    #expect(try store.removeLaunchSetting(for: "org.example.game"))
    #expect(try !store.removeLaunchSetting(for: "org.example.game"))
    #expect(try store.launchSettings().isEmpty)
  }

  @Test
  func storeRefusesAnInvalidEnvironmentName() {
    #expect(throws: LaunchSettingError.invalidEnvironmentName("1A")) {
      try store.setLaunchSetting(LaunchSetting(environment: ["1A": "x"]), for: "k")
    }
  }
}
