import Foundation

extension RemappingProfile {
  /// Checks the macros: count, unique identifiers and names, each macro's fields, step
  /// destinations, and the run-time limits.
  /// - Throws: ``RemappingValidationError``.
  func validateMacros() throws {
    guard macros.count <= RemappingMacro.maximumCount else {
      throw RemappingValidationError.tooManyMacros(macros.count)
    }
    var identifiers: Set<UUID> = []
    var names: Set<String> = []
    for (index, macro) in macros.enumerated() {
      guard identifiers.insert(macro.id).inserted else {
        throw RemappingValidationError.duplicateMacroID(macro.id)
      }
      let trimmed = macro.name.trimmingCharacters(in: .whitespacesAndNewlines)
      guard trimmed == macro.name, RemappingMacro.nameLengthRange.contains(macro.name.count),
        macro.name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
      else { throw RemappingValidationError.invalidMacro(index: index, field: "name") }
      guard names.insert(Self.normalizedName(macro.name)).inserted else {
        throw RemappingValidationError.duplicateMacroName(index: index)
      }
      try validate(macro, at: index)
    }
  }

  /// Checks one macro's repeat, steps and run time.
  private func validate(_ macro: RemappingMacro, at index: Int) throws {
    guard RemappingMacro.stepCountRange.contains(macro.steps.count) else {
      throw RemappingValidationError.invalidMacro(index: index, field: "steps")
    }
    if case .count(let count) = macro.repeatMode,
      !RemappingMacro.repeatCountRange.contains(count)
    {
      throw RemappingValidationError.invalidMacro(index: index, field: "repeat")
    }
    for (step, value) in macro.steps.enumerated() {
      let delay: (field: String, ms: Double)?
      switch value {
      case .wait(let durationMs): delay = ("durationMs", durationMs)
      case .chord(let destinations, let holdMs):
        guard !destinations.isEmpty else {
          throw RemappingValidationError.invalidMacro(
            index: index,
            field: "steps[\(step)].destinations"
          )
        }
        delay = ("holdMs", holdMs)
      case .tap, .press, .release: delay = nil
      }
      if let delay, !delay.ms.isFinite || !RemappingMacro.delayMsRange.contains(delay.ms) {
        throw RemappingValidationError.invalidMacro(
          index: index,
          field: "steps[\(step)].\(delay.field)"
        )
      }
      for destination in value.destinations {
        try validateStepDestination(destination, macro: index, step: step)
      }
    }
    let passMs = macro.passMs
    guard passMs <= RemappingMacro.maximumPassMs else {
      throw RemappingValidationError.macroRunTimeExceeded(index: index, limit: "one-pass")
    }
    if case .count(let count) = macro.repeatMode,
      passMs * Double(count) > RemappingMacro.maximumRunMs
    {
      throw RemappingValidationError.macroRunTimeExceeded(index: index, limit: "repeat")
    }
  }

  /// Checks that a step destination is a key, pointer button, or virtual gamepad button or d-pad
  /// direction that the output policy allows.
  private func validateStepDestination(
    _ destination: RemappingDestination,
    macro: Int,
    step: Int
  ) throws {
    switch destination {
    case .macro: throw RemappingValidationError.macroNestingNotAllowed(index: macro, step: step)
    case .keyboard, .mouseButton, .gamepadButton, .gamepadDpad:
      try validateDestination(destination)
    case .gamepadAxis, .mouseMovement, .scroll, .physical, .profileSwitch, .layerSet, .pause,
      .systemKey, .systemAction, .openApplication, .openURL, .runShortcut, .typeText,
      .speak:
      throw RemappingValidationError.invalidMacroStepDestination(index: macro, step: step)
    }
  }
}
