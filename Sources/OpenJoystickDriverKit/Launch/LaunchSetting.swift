import Foundation

/// The reasons a launch setting is refused.
public enum LaunchSettingError: Error, Equatable, Sendable {
  /// An environment variable name does not match `[A-Za-z_][A-Za-z0-9_]*`.
  case invalidEnvironmentName(String)
  /// An `--env` value is not `NAME=VALUE`.
  case invalidEnvironmentAssignment(String)
}

/// What OJD applies when it launches one program: the SDL GameController backend, extra
/// environment variables, and extra arguments.
///
/// See `launchSettings` in `Resources/Schemas/settings.schema.json`. The settings file keys each
/// one by ``LaunchSettingKey``.
public struct LaunchSetting: Equatable, Sendable {
  /// Whether the program starts with the SDL GameController backend hints.
  public var sdlGameControllerBackend: Bool
  /// Variables added to the program's environment, by name.
  public var environment: [String: String]
  /// Arguments appended after the arguments given on the command line.
  public var arguments: [String]

  /// Creates a setting that changes nothing.
  public init(
    sdlGameControllerBackend: Bool = false,
    environment: [String: String] = [:],
    arguments: [String] = []
  ) {
    self.sdlGameControllerBackend = sdlGameControllerBackend
    self.environment = environment
    self.arguments = arguments
  }

  /// Whether `name` is a valid environment variable name.
  public static func isValidEnvironmentName(_ name: String) -> Bool {
    guard let first = name.unicodeScalars.first, first == "_" || first.isASCIILetter else {
      return false
    }
    return name.unicodeScalars.allSatisfy { $0 == "_" || $0.isASCIILetter || $0.isASCIIDigit }
  }

  /// Splits `text`, written `NAME=VALUE`, at its first `=`.
  ///
  /// - Throws: ``LaunchSettingError`` when `text` has no `=` or the name is invalid.
  public static func assignment(_ text: String) throws -> (name: String, value: String) {
    guard let equals = text.firstIndex(of: "=") else {
      throw LaunchSettingError.invalidEnvironmentAssignment(text)
    }
    let name = String(text[..<equals])
    guard isValidEnvironmentName(name) else {
      throw LaunchSettingError.invalidEnvironmentName(name)
    }
    return (name, String(text[text.index(after: equals)...]))
  }

  /// Checks every environment name.
  ///
  /// - Throws: ``LaunchSettingError/invalidEnvironmentName(_:)`` for the first invalid name.
  public func validate() throws {
    for name in environment.keys.sorted() where !Self.isValidEnvironmentName(name) {
      throw LaunchSettingError.invalidEnvironmentName(name)
    }
  }

  /// The environment the program starts from: `base` with the stored variables over it.
  ///
  /// The SDL mapping is added after this (see ``SDLLaunchEnvironment``), so a stored
  /// `SDL_GAMECONTROLLERCONFIG` stays first and OJD's mapping lines follow it.
  public func environment(over base: [String: String]) -> [String: String] {
    base.merging(environment) { _, stored in stored }
  }

  /// The environment the program starts with: the stored variables over `base`, then the SDL
  /// mapping of `profiles`.
  ///
  /// The backend hints are on when `gameControllerBackend` is set, whatever the stored value, or
  /// when the stored value is on.
  ///
  /// - Throws: ``SDLLaunchEnvironment/Failure``, as for
  ///   ``SDLLaunchEnvironment/environment(adding:to:gameControllerBackend:)``.
  public func launchEnvironment(
    adding profiles: [VirtualHIDProfileID],
    over base: [String: String],
    gameControllerBackend: Bool
  ) throws -> [String: String] {
    try SDLLaunchEnvironment.environment(
      adding: profiles,
      to: environment(over: base),
      gameControllerBackend: gameControllerBackend || sdlGameControllerBackend
    )
  }

  /// The arguments of the program: `given`, then the stored arguments.
  public func launchArguments(after given: [String]) -> [String] { given + arguments }
}

extension Unicode.Scalar {
  /// Whether the scalar is an ASCII letter.
  fileprivate var isASCIILetter: Bool { ("A"..."Z").contains(self) || ("a"..."z").contains(self) }
  /// Whether the scalar is an ASCII digit.
  fileprivate var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}

extension LaunchSetting: Codable {
  /// The keys of a launch setting.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    /// The three fields.
    case sdlGameControllerBackend, environment, arguments
  }

  /// Decodes a launch setting; an unknown key or an invalid variable name is refused.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    sdlGameControllerBackend =
      try container.decodeIfPresent(Bool.self, forKey: .sdlGameControllerBackend) ?? false
    environment =
      try container.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
    arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
    do { try validate() } catch {
      throw DecodingError.dataCorruptedError(
        forKey: .environment,
        in: container,
        debugDescription: "\(error)"
      )
    }
  }

  /// Encodes the fields that differ from the defaults.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    if sdlGameControllerBackend {
      try container.encode(sdlGameControllerBackend, forKey: .sdlGameControllerBackend)
    }
    if !environment.isEmpty { try container.encode(environment, forKey: .environment) }
    if !arguments.isEmpty { try container.encode(arguments, forKey: .arguments) }
  }
}
