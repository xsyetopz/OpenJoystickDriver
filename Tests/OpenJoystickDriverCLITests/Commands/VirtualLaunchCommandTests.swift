import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized)
struct VirtualLaunchCommandTests {
  private static let baseEnvironment = ["PATH": "/usr/bin:/bin", "OJD_LAUNCH_TEST": "kept"]

  private static func device(
    _ id: String,
    _ profile: VirtualHIDProfileID
  )
    -> ApplicationServiceDeviceDescription
  {
    var device = ApplicationServiceDeviceDescription.fixture(id: id)
    device.virtualHIDProfile = ApplicationServiceVirtualHIDProfileStatus(
      profile: profile,
      source: .override,
      override: profile,
      unavailable: false
    )
    return device
  }

  /// Runs `ojd` with `arguments` and returns what the launched program printed.
  private static func launch(
    _ service: FakeService,
    _ arguments: [String],
    environment: [String: String] = baseEnvironment
  ) async throws -> (run: CLIRun, printed: String) {
    let pipe = Pipe()
    let run = await VirtualLaunchCommand.$baseEnvironment.withValue(environment) {
      await VirtualLaunchCommand.$programStandardOutput.withValue(pipe.fileHandleForWriting) {
        await service.run(arguments)
      }
    }
    try pipe.fileHandleForWriting.close()
    let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
    return (run, try #require(String(bytes: data, encoding: .utf8)))
  }

  /// The variables `env` printed.
  ///
  /// A value may span lines, so a line without a name continues the variable before it.
  private static func variables(_ printed: String) -> [String: String] {
    var result: [String: String] = [:]
    var name: String?
    var lines = printed.split(separator: "\n", omittingEmptySubsequences: false)
    if lines.last?.isEmpty == true { lines.removeLast() }
    for line in lines {
      if let equals = line.firstIndex(of: "="),
        line[..<equals].allSatisfy({ $0.isUppercase || $0.isNumber || $0 == "_" }),
        equals != line.startIndex
      {
        let key = String(line[..<equals])
        result[key] = String(line[line.index(after: equals)...])
        name = key
      } else if let name {
        result[name, default: ""] += "\n" + line
      }
    }
    return result
  }

  @Test
  func theLaunchedProgramSeesTheMappingOfTheGenericPersona() async throws {
    let service = try FakeService(devices: [Self.device("pad-1", .generic)])
    let (run, printed) = try await Self.launch(service, ["virtual", "launch", "/usr/bin/env"])

    #expect(run.code == 0, "\(run.standardError)")
    let generic = try VirtualHIDProfileID.generic.gamepadMapping().sdlMapping
    let variables = Self.variables(printed)
    #expect(variables[SDLLaunchEnvironment.variable] == generic)
    #expect(variables["OJD_LAUNCH_TEST"] == "kept")
  }

  @Test
  func theGameControllerBackendOptionAddsExactlyItsHintsToTheProgramEnvironment() async throws {
    let service = try FakeService(devices: [Self.device("pad-1", .sdlCompatible)])
    let (run, printed) = try await Self.launch(
      service,
      ["virtual", "launch", "--sdl-gamecontroller-backend", "/usr/bin/env"],
      environment: Self.baseEnvironment.merging(["SDL_JOYSTICK_HIDAPI": "1"]) { $1 }
    )

    #expect(run.code == 0, "\(run.standardError)")
    let mapping = try VirtualHIDProfileID.sdlCompatible.gamepadMapping().sdlMapping
    var expected = Self.baseEnvironment
    expected.merge(SDLLaunchEnvironment.gameControllerBackend) { $1 }
    expected[SDLLaunchEnvironment.variable] = mapping
    let variables = Self.variables(printed)
    for (name, value) in expected { #expect(variables[name] == value, "\(name)") }
    let hints = variables.keys.filter { $0.hasPrefix("SDL_JOYSTICK_") }
    #expect(Set(hints) == Set(SDLLaunchEnvironment.gameControllerBackend.keys))
    #expect(!run.standardError.contains(sdlHintsNote("SDLCompatible")))
  }

  @Test
  func withoutTheOptionNoJoystickHintIsSet() async throws {
    let service = try FakeService(devices: [Self.device("pad-1", .generic)])
    let (run, printed) = try await Self.launch(service, ["virtual", "launch", "/usr/bin/env"])

    #expect(run.code == 0, "\(run.standardError)")
    #expect(!Self.variables(printed).keys.contains { $0.hasPrefix("SDL_JOYSTICK_") })
  }

  @Test
  func theGameControllerBackendOptionStillFailsWithoutAVirtualGamepad() async throws {
    let service = try FakeService(devices: [])
    let (run, printed) = try await Self.launch(
      service,
      ["virtual", "launch", "--sdl-gamecontroller-backend", "/usr/bin/env"]
    )

    #expect(run.code == 1)
    #expect(run.standardError.contains(CLIFailure.prefix(.controllerRequestFailed)))
    #expect(printed.isEmpty)
  }

  @Test
  func aNameOnPathAndTheArgumentsOfTheProgramReachIt() async throws {
    let service = try FakeService(devices: [Self.device("pad-1", .generic)])
    let (run, printed) = try await Self.launch(
      service,
      ["virtual", "launch", "env", "OJD_ARGUMENT=given"]
    )

    #expect(run.code == 0, "\(run.standardError)")
    #expect(Self.variables(printed)["OJD_ARGUMENT"] == "given")
  }

  @Test
  func everyPersonaMappingFollowsAValueThatIsAlreadySet() async throws {
    let service = try FakeService(devices: [
      Self.device("pad-1", .sdlCompatible), Self.device("pad-2", .generic),
      Self.device("pad-3", .gameControllerCompatible),
    ])
    var environment = Self.baseEnvironment
    environment[SDLLaunchEnvironment.variable] = "abc,Mine,a:b0"
    let (run, printed) = try await Self.launch(
      service,
      ["virtual", "launch", "/usr/bin/env"],
      environment: environment
    )

    #expect(run.code == 0, "\(run.standardError)")
    let mappings = try VirtualHIDProfileID.allCases.map { try $0.gamepadMapping().sdlMapping }
    #expect(
      Self.variables(printed)[SDLLaunchEnvironment.variable]
        == (["abc,Mine,a:b0"] + mappings).joined(separator: "\n")
    )
    for profile in VirtualHIDProfileID.allCases {
      #expect(
        run.standardError.contains(sdlHintsNote(profile.rawValue))
          == !profile.worksWithDefaultSDLHints,
        "\(profile)"
      )
    }
  }

  @Test
  func withoutAVirtualGamepadItFailsAndRunsNothing() async throws {
    let service = try FakeService(devices: [])
    let (run, printed) = try await Self.launch(service, ["virtual", "launch", "/usr/bin/env"])

    #expect(run.code == 1)
    #expect(run.standardError.contains(CLIFailure.prefix(.controllerRequestFailed)))
    #expect(run.standardError.contains(CLILocalized.text("cli.virtual.launch.errorNoGamepad")))
    #expect(printed.isEmpty)
  }

  @Test
  func aProgramThatDoesNotExistFailsWithTheLaunchCode() async throws {
    let service = try FakeService(devices: [Self.device("pad-1", .generic)])
    for program in ["/nonexistent/ojd-program", "ojd-no-such-program", "/nonexistent/Game.app"] {
      let (run, printed) = try await Self.launch(service, ["virtual", "launch", program])
      #expect(run.code == 1, "\(program)")
      #expect(run.standardError.contains(CLIFailure.prefix(.launchFailed)), "\(program)")
      #expect(run.standardError.contains(program), "\(program)")
      #expect(printed.isEmpty, "\(program)")
    }
  }

  @Test
  func theExitStatusOfTheProgramIsTheExitStatusOfOJD() async throws {
    let service = try FakeService(devices: [Self.device("pad-1", .generic)])
    let failed = try await Self.launch(service, ["virtual", "launch", "/usr/bin/false"])
    #expect(failed.run.code == 1)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-launch-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let script = directory.appendingPathComponent("terminate.sh")
    try "#!/bin/sh\nkill -TERM $$\n".write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    let signaled = try await Self.launch(service, ["virtual", "launch", script.path])
    #expect(signaled.run.code == 128 + SIGTERM)
  }

  @Test
  func jsonAndPlainAndAMissingProgramAreUsageErrors() async throws {
    let service = try FakeService(devices: [Self.device("pad-1", .generic)])
    for arguments in [
      ["virtual", "launch", "--json", "/usr/bin/env"],
      ["virtual", "launch", "--plain", "/usr/bin/env"],
      ["virtual", "launch"],
    ] {
      let (run, printed) = try await Self.launch(service, arguments)
      #expect(run.code == 64, "\(arguments)")
      #expect(printed.isEmpty, "\(arguments)")
    }
  }
}
