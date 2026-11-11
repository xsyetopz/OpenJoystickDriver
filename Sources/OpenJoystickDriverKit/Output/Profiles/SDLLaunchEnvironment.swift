import Foundation

/// The environment OJD gives a program it launches, so that SDL in the program lists the virtual
/// gamepads.
///
/// SDL reads `SDL_GAMECONTROLLERCONFIG` as mapping lines separated by newlines. OJD sets it to
/// the mapping line of each profile in `profiles`. A value already in the environment stays
/// first and OJD's lines follow it, so a mapping for the same GUID takes OJD's.
///
/// With the GameController backend, OJD also sets ``gameControllerBackend``.
public enum SDLLaunchEnvironment {
  /// The variable that carries the mappings.
  public static let variable = "SDL_GAMECONTROLLERCONFIG"

  /// The SDL hints that make SDL read controllers only through Apple's GameController framework
  /// (MFi): SDL's HIDAPI and IOKit backends are off, so the HIDAPI Xbox driver does not claim a
  /// virtual `SDLCompatible` gamepad, and GameController events reach SDL while the program is not
  /// frontmost. `SDL_JOYSTICK_HIDAPI=0` switches off every HIDAPI driver.
  public static let gameControllerBackend: [String: String] = [
    "SDL_JOYSTICK_MFI": "1",
    "SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS": "1",
    "SDL_JOYSTICK_IOKIT": "0",
    "SDL_JOYSTICK_HIDAPI": "0",
  ]

  /// Why the environment cannot be built.
  public enum Failure: Error, Equatable, Sendable {
    /// No profile was given, so there is no mapping to set.
    case noProfile
    /// The SDL mapping of a profile could not be built.
    case mapping(VirtualGamepadMappingError)
  }

  /// Returns `base` with ``variable`` set to the mapping lines of `profiles`.
  ///
  /// Each profile appears once, in the order of ``VirtualHIDProfileID/allCases``. When
  /// `gameControllerBackend` is true, the variables of ``gameControllerBackend`` are set too and
  /// replace values already in `base`.
  public static func environment(
    adding profiles: [VirtualHIDProfileID],
    to base: [String: String],
    gameControllerBackend: Bool
  ) throws -> [String: String] {
    let ordered = VirtualHIDProfileID.allCases.filter(profiles.contains)
    guard !ordered.isEmpty else { throw Failure.noProfile }
    var lines: [String] = []
    for profile in ordered {
      do { lines.append(try profile.gamepadMapping().sdlMapping) } catch let error
        as VirtualGamepadMappingError
      {
        throw Failure.mapping(error)
      }
    }
    var environment = base
    if gameControllerBackend {
      environment.merge(Self.gameControllerBackend) { _, hint in hint }
    }
    let existing = (base[variable] ?? "").trimmingCharacters(in: .newlines)
    environment[variable] = ([existing].filter { !$0.isEmpty } + lines).joined(separator: "\n")
    return environment
  }
}
