import OpenJoystickDriverKit

extension MappingProfileEditor {
  static let touchOptions: Set<String> = [
    "--touch-surface", "--touch-mode", "--touch-pointer-sensitivity", "--touch-stick-radius",
    "--touch-deadzone"
  ]

  static func touchMappings(
    _ options: MappingOptions, defaultValue: [RemappingTouchMapping] = []
  ) throws -> [RemappingTouchMapping] {
    guard touchOptions.contains(where: options.contains) else { return defaultValue }
    guard let rawSurface = options["--touch-surface"],
      let surface = RemappingTouchSurface(rawValue: rawSurface)
    else {
      throw MappingCommandError.invalidArguments(
        "--touch-surface: primary|left|right required"
      )
    }
    let old = defaultValue.first { $0.surface == surface }
      ?? RemappingTouchMapping(surface: surface, mode: .pointer)
    let rawMode = options["--touch-mode"] ?? old.mode.rawValue
    if rawMode == "none" {
      guard !touchOptions.subtracting(["--touch-surface", "--touch-mode"])
        .contains(where: options.contains)
      else { throw MappingCommandError.invalidArguments("Cannot tune a removed touch mapping") }
      return defaultValue.filter { $0.surface != surface }
    }
    guard let mode = RemappingTouchMode(rawValue: rawMode) else {
      throw MappingCommandError.invalidArguments(
        "--touch-mode: pointer|left_stick|right_stick|none"
      )
    }
    func number(_ option: String, fallback: Double) throws -> Double {
      guard let raw = options[option] else { return fallback }
      return try MappingSyntax.finiteDouble(raw, option: option)
    }
    let mapping = RemappingTouchMapping(
      id: old.id,
      surface: surface,
      mode: mode,
      pointerSensitivity: try number(
        "--touch-pointer-sensitivity", fallback: old.pointerSensitivity
      ),
      stickRadius: try number("--touch-stick-radius", fallback: old.stickRadius),
      deadzone: try number("--touch-deadzone", fallback: old.deadzone)
    )
    var mappings = defaultValue
    if let index = mappings.firstIndex(where: { $0.surface == surface }) {
      mappings[index] = mapping
    } else {
      mappings.append(mapping)
    }
    return mappings
  }
}
