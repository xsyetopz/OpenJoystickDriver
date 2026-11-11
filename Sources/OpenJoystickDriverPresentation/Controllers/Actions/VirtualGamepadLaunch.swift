import Foundation
import OpenJoystickDriverKit

/// Runs a game with the SDL mapping of the connected virtual gamepads, as `ojd virtual launch`
/// does.
enum VirtualGamepadLaunch {
  /// A program ready to start.
  struct Prepared {
    /// The program's executable.
    let executable: URL
    /// The environment to start the program with.
    let environment: [String: String]
  }

  /// Why a program cannot be launched.
  enum Failure: Error, Equatable {
    /// No connected controller has a virtual gamepad, so there is no mapping to set.
    case noGamepad
    /// The program cannot start; `reason` says why.
    case cannotStart(program: String, reason: String)

    /// The message the user reads.
    var message: String {
      switch self {
      case .noGamepad: OJDLocalized.string("ui.controllers.launch.noGamepad")
      case .cannotStart(let program, let reason):
        OJDLocalized.formatted("cli.virtual.launch.errorFailed", program, reason)
      }
    }
  }

  /// What became of a started program.
  enum Outcome: Equatable {
    /// The program started.
    case started(program: String)
    /// The program ended with the status; a signal counts as 128 plus its number.
    case exited(program: String, status: Int32)
    /// The program could not start; the value is the message.
    case failed(String)

    /// The message the user reads.
    var message: String {
      switch self {
      case .started(let program): OJDLocalized.formatted("ui.controllers.launch.started", program)
      case .exited(let program, let status):
        OJDLocalized.formatted("ui.controllers.launch.exited", program, Int(status))
      case .failed(let message): message
      }
    }
  }

  /// Returns the executable of `program`, an `.app` or an executable file, and `baseEnvironment`
  /// with the mappings of every virtual gamepad in `devices`. `gameControllerBackend` adds the SDL
  /// hints that make SDL read controllers only through Apple's GameController framework.
  ///
  /// - Parameters:
  ///   - program: The app or executable file.
  ///   - devices: The connected controllers.
  ///   - gameControllerBackend: Whether to add the SDL hints for the GameController backend.
  ///   - baseEnvironment: The environment to add the mappings to.
  /// - Returns: The executable of `program`, an `.app` or an executable file, and `baseEnvironment`
  ///   with the mappings of every virtual gamepad in `devices`.
  /// - Throws: ``Failure`` when the program cannot start or no controller has a virtual gamepad;
  ///   any other error of the lookup of the executable.
  static func prepare(
    program: URL,
    devices: [ApplicationServiceDeviceDescription],
    gameControllerBackend: Bool,
    baseEnvironment: [String: String]
  ) throws -> Prepared {
    let executable: URL
    do {
      executable = try ProgramExecutable.url(for: program.path, searchPath: nil)
    } catch {
      let reason: String
      switch error as? ProgramExecutable.Failure {
      case .noExecutable?: reason = OJDLocalized.string("cli.virtual.launch.errorNoExecutable")
      case .notExecutable?: reason = OJDLocalized.string("cli.virtual.launch.errorNotExecutable")
      case .notFound?: reason = OJDLocalized.string("cli.virtual.launch.errorNotFound")
      case nil: throw error
      }
      throw Failure.cannotStart(program: program.lastPathComponent, reason: reason)
    }
    let profiles = devices.compactMap { $0.servingDecision.selection?.profileID }
    do {
      let environment = try SDLLaunchEnvironment.environment(
        adding: profiles,
        to: baseEnvironment,
        gameControllerBackend: gameControllerBackend
      )
      return Prepared(executable: executable, environment: environment)
    } catch SDLLaunchEnvironment.Failure.noProfile {
      throw Failure.noGamepad
    }
  }

  /// Returns the profiles among `devices` that SDL does not recognize with its default hints,
  /// which the user can fix by choosing the GameController backend.
  ///
  /// - Parameter devices: The connected controllers.
  /// - Returns: The profiles among `devices` that SDL does not recognize with its default hints,
  ///   which the user can fix by choosing the GameController backend.
  /// - Throws: The error of a mapping that cannot be built.
  static func profilesNeedingBackend(
    in devices: [ApplicationServiceDeviceDescription]
  ) throws -> [VirtualHIDProfileID] {
    let profiles = devices.compactMap { $0.servingDecision.selection?.profileID }
    return try VirtualHIDProfileID.allCases.filter { profile in
      try profiles.contains(profile) && !profile.gamepadMapping().worksWithDefaultSDLHints
    }
  }

  /// Returns `environment` without the variables launchd gives an app and a terminal does not, so
  /// the game starts from the environment `ojd virtual launch` passes it.
  ///
  /// - Parameter environment: The environment of the app.
  /// - Returns: `environment` without the variables launchd gives an app and a terminal does not,
  ///   so the game starts from the environment `ojd virtual launch` passes it.
  static func gameEnvironment(from environment: [String: String]) -> [String: String] {
    let exact: Set<String> = ["LaunchInstanceID", "OS_ACTIVITY_DT_MODE"]
    return environment.filter { name, _ in
      !(name.hasPrefix("__CF") || name.hasPrefix("XPC_") || exact.contains(name))
    }
  }
}
