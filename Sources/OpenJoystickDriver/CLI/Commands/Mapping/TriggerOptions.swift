import OpenJoystickDriverKit

extension MappingProfileEditor {
  static let triggerOptions: Set<String> = [
    "--trigger-source", "--trigger-mode", "--trigger-soft-threshold",
    "--trigger-full-threshold", "--trigger-hysteresis", "--trigger-skip-window-ms",
    "--trigger-passthrough",
  ]

  static func triggerMappings(
    _ options: MappingOptions,
    defaultValue: [RemappingTriggerMapping] = []
  ) throws -> [RemappingTriggerMapping] {
    guard triggerOptions.contains(where: options.contains) else { return defaultValue }
    guard let rawSource = options["--trigger-source"],
      let source = RemappingTriggerSource(rawValue: rawSource)
    else { throw MappingCommandError.invalidArguments("--trigger-source: left|right required") }
    let old = defaultValue.first { $0.source == source } ?? RemappingTriggerMapping(source: source)
    let rawMode = options["--trigger-mode"] ?? old.mode.rawValue
    if rawMode == "none" {
      guard !triggerOptions.subtracting(["--trigger-source", "--trigger-mode"])
        .contains(where: options.contains)
      else { throw MappingCommandError.invalidArguments("Cannot tune a removed trigger mapping") }
      return defaultValue.filter { $0.source != source }
    }
    guard let mode = RemappingDualStageTriggerMode(rawValue: rawMode) else {
      throw MappingCommandError.invalidArguments(
        "--trigger-mode: simultaneous|exclusive|prefer_full|prefer_full_combined|"
          + "responsive_prefer_full|responsive_prefer_full_combined|none"
      )
    }
    func number(_ suffix: String, _ fallback: Double) throws -> Double {
      let key = "--trigger-" + suffix
      guard let raw = options[key] else { return fallback }
      return try MappingSyntax.finiteDouble(raw, option: key)
    }
    func boolean(_ suffix: String, _ fallback: Bool) throws -> Bool {
      let key = "--trigger-" + suffix
      guard let raw = options[key], raw == "true" || raw == "false" else {
        if options[key] == nil { return fallback }
        throw MappingCommandError.invalidArguments(key + ": true|false")
      }
      return raw == "true"
    }
    let mapping = try RemappingTriggerMapping(
      source: source,
      mode: mode,
      softThreshold: number("soft-threshold", old.softThreshold),
      fullThreshold: number("full-threshold", old.fullThreshold),
      hysteresis: number("hysteresis", old.hysteresis),
      skipWindowMs: number("skip-window-ms", old.skipWindowMs),
      passthrough: boolean("passthrough", old.passthrough)
    )
    try mapping.validate()
    var mappings = defaultValue
    if let index = mappings.firstIndex(where: { $0.source == source }) {
      mappings[index] = mapping
    } else {
      mappings.append(mapping)
    }
    return mappings
  }
}
