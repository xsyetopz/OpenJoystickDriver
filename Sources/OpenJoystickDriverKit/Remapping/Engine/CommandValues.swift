import Foundation

public enum RemappingCommandValueError: Error, Equatable, LocalizedError, Sendable {
  case invalidSource(String)
  case invalidDestination(String)

  public var errorDescription: String? {
    switch self {
    case .invalidSource(let raw): "Invalid source '\(raw)'."
    case .invalidDestination(let raw): "Invalid target '\(raw)'."
    }
  }
}

public enum RemappingCommandValueParser {
  public static func source(_ raw: String) throws -> RemappingSource {
    let parts = raw.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    if parts.count == 2, parts[0] == "button", let button = RemappingButton(rawValue: parts[1]) {
      return .button(button)
    }
    if parts.count == 2, parts[0] == "dpad",
      let direction = RemappingDpadDirection(rawValue: parts[1])
    {
      return .dpad(direction)
    }
    if parts.count == 2, parts[0] == "axis", let axis = RemappingAxis(rawValue: parts[1]) {
      return .axis(axis)
    }
    if parts.count == 3, parts[0] == "axis", let axis = RemappingAxis(rawValue: parts[1]),
      let direction = RemappingAxisDirection(rawValue: parts[2])
    {
      return .axisDirection(axis, direction)
    }
    if parts.count == 3, parts[0] == "trigger",
      let trigger = RemappingTriggerSource(rawValue: parts[1]),
      let stage = RemappingTriggerStage(rawValue: parts[2])
    {
      return .triggerStage(trigger, stage)
    }
    if parts.count == 3, parts[0] == "motion", parts[1] == "lean",
      let direction = RemappingMotionLeanDirection(rawValue: parts[2])
    {
      return .motionLean(direction)
    }
    if parts.count == 3, parts[0] == "touch",
      let surface = RemappingTouchSurface(rawValue: parts[1]), parts[2] == "contact"
    {
      return .touchContact(surface)
    }
    if parts.count == 7, parts[0] == "touch",
      let surface = RemappingTouchSurface(rawValue: parts[1]), parts[2] == "grid",
      let columns = Int(parts[3]), let rows = Int(parts[4]), let column = Int(parts[5]),
      let row = Int(parts[6])
    {
      return .touchGrid(
        RemappingTouchGridSource(
          surface: surface, columns: columns, rows: rows, column: column, row: row
        )
      )
    }
    if parts.count == 5, parts[0] == "touch",
      let surface = RemappingTouchSurface(rawValue: parts[1]), parts[2] == "swipe",
      let direction = RemappingTouchSwipeDirection(rawValue: parts[3]),
      let minimumDistance = Double(parts[4]), minimumDistance.isFinite
    {
      return .touchSwipe(
        RemappingTouchSwipeSource(
          surface: surface, direction: direction, minimumDistance: minimumDistance
        )
      )
    }
    throw RemappingCommandValueError.invalidSource(raw)
  }

  public static func destination(_ raw: String) throws -> RemappingDestination {
    let parts = raw.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    if parts.count == 3, parts[0] == "gamepad", parts[1] == "axis",
      let axis = RemappingAxis(rawValue: parts[2])
    {
      return .gamepadAxis(axis)
    }
    if parts.count == 3, parts[0] == "gamepad", parts[1] == "dpad",
      let direction = RemappingDpadDirection(rawValue: parts[2])
    {
      return .gamepadDpad(direction)
    }
    if parts.count == 3, parts[0] == "gamepad", parts[1] == "button",
      let button = RemappingButton(rawValue: parts[2])
    {
      return .gamepadButton(button)
    }
    if parts.count == 2, parts[0] == "key", let key = RemappingKeyboardKey(rawValue: parts[1]) {
      return .keyboard(key: key, modifiers: [])
    }
    if parts.count == 3, parts[0] == "key", let key = RemappingKeyboardKey(rawValue: parts[1]),
      parts[2].hasPrefix("mods=")
    {
      let names = parts[2].dropFirst(5).split(separator: ",").map(String.init)
      let modifiers = names.compactMap(RemappingKeyModifier.init(rawValue:))
      if !names.isEmpty, modifiers.count == names.count, Set(modifiers).count == modifiers.count {
        return .keyboard(key: key, modifiers: Set(modifiers))
      }
    }
    if parts.count == 2, parts[0] == "mouse", let button = RemappingMouseButton(rawValue: parts[1])
    {
      return .mouseButton(button)
    }
    if parts.count == 2, parts[0] == "move", let axis = RemappingPointerAxis(rawValue: parts[1]) {
      return .mouseMovement(axis)
    }
    if parts.count == 2, parts[0] == "scroll", let axis = RemappingPointerAxis(rawValue: parts[1]) {
      return .scroll(axis)
    }
    if parts.count == 4, parts[0] == "physical", parts[1] == "rumble",
      let motor = PhysicalRumbleMotor(rawValue: parts[2]), let intensity = boundedUnit(parts[3])
    {
      return .physical(.rumble(motor: motor, intensity: intensity))
    }
    if parts.count == 3, parts[0] == "physical", parts[1] == "player",
      let rawIndicator = Int(parts[2]),
      let indicator = PhysicalPlayerIndicator(rawValue: rawIndicator)
    {
      return .physical(.playerIndicator(indicator))
    }
    if parts.count == 5, parts[0] == "physical", parts[1] == "color",
      let red = UInt8(parts[2]), let green = UInt8(parts[3]), let blue = UInt8(parts[4])
    {
      return .physical(.color(red: red, green: green, blue: blue))
    }
    if parts.count == 3, parts[0] == "physical", parts[1] == "brightness",
      let intensity = boundedUnit(parts[2])
    {
      return .physical(.brightness(intensity))
    }
    if parts.count == 4, parts[0] == "physical", parts[1] == "adaptive",
      let trigger = PhysicalAdaptiveTrigger(rawValue: parts[2]), parts[3] == "off"
    {
      return .physical(.adaptiveTrigger(trigger, .off))
    }
    if parts.count == 6, parts[0] == "physical", parts[1] == "adaptive",
      let trigger = PhysicalAdaptiveTrigger(rawValue: parts[2]), parts[3] == "resistance",
      let startPosition = boundedUnit(parts[4]), let strength = boundedUnit(parts[5])
    {
      return .physical(
        .adaptiveTrigger(
          trigger,
          PhysicalAdaptiveTriggerEffect(
            kind: .resistance,
            startPosition: startPosition,
            strength: strength
          )
        )
      )
    }
    throw RemappingCommandValueError.invalidDestination(raw)
  }

  private static func boundedUnit(_ raw: String) -> Double? {
    guard let value = Double(raw), value.isFinite, (0...1).contains(value) else { return nil }
    return value
  }
}
