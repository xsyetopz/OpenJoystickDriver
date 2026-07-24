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
    throw RemappingCommandValueError.invalidSource(raw)
  }

  public static func destination(_ raw: String) throws -> RemappingDestination {
    let parts = raw.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
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
    if parts.count == 2, parts[0] == "mouse",
      let button = RemappingMouseButton(rawValue: parts[1])
    {
      return .mouseButton(button)
    }
    if parts.count == 2, parts[0] == "move", let axis = RemappingPointerAxis(rawValue: parts[1]) {
      return .mouseMovement(axis)
    }
    if parts.count == 2, parts[0] == "scroll", let axis = RemappingPointerAxis(rawValue: parts[1]) {
      return .scroll(axis)
    }
    throw RemappingCommandValueError.invalidDestination(raw)
  }
}
