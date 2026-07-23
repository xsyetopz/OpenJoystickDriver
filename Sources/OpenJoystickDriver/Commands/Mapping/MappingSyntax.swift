import Foundation
import OpenJoystickDriverKit

enum MappingCommandError: Error, Equatable, LocalizedError {
  case invalidArguments(String)
  case profileNotFound(String)
  case ambiguousProfile(String)

  var errorDescription: String? {
    switch self {
    case .invalidArguments(let message), .profileNotFound(let message),
      .ambiguousProfile(let message):
      message
    }
  }
}

struct MappingOptions {
  private(set) var values: [String: String] = [:]

  init(_ arguments: [String], flags: Set<String> = []) throws {
    var index = 0
    while index < arguments.count {
      let option = arguments[index]
      guard option.hasPrefix("--") else {
        throw MappingCommandError.invalidArguments("Unexpected argument '\(option)'.")
      }
      guard values[option] == nil else {
        throw MappingCommandError.invalidArguments("Option '\(option)' was repeated.")
      }
      if flags.contains(option) {
        values[option] = "true"
        index += 1
      } else {
        guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
          throw MappingCommandError.invalidArguments("\(option) requires a value.")
        }
        values[option] = arguments[index + 1]
        index += 2
      }
    }
  }

  func validate(allowed: Set<String>) throws {
    if let unknown = values.keys.sorted().first(where: { !allowed.contains($0) }) {
      throw MappingCommandError.invalidArguments("Unknown option '\(unknown)'.")
    }
  }

  func required(_ option: String) throws -> String {
    guard let value = values[option] else {
      throw MappingCommandError.invalidArguments("\(option) is required.")
    }
    return value
  }

  subscript(_ option: String) -> String? { values[option] }
  func contains(_ option: String) -> Bool { values[option] != nil }
}

enum MappingSyntax {
  static func source(_ raw: String) throws -> RemappingSource {
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
    throw MappingCommandError.invalidArguments("Invalid source '\(raw)'.")
  }

  static func destination(_ raw: String) throws -> RemappingDestination {
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
    throw MappingCommandError.invalidArguments("Invalid target '\(raw)'.")
  }

  static func identifier(_ raw: String, option: String) throws -> UInt16 {
    let value = raw.lowercased().hasPrefix("0x") ? UInt16(raw.dropFirst(2), radix: 16) : UInt16(raw)
    guard let value else {
      throw MappingCommandError.invalidArguments(
        "\(option) must be a 16-bit decimal or 0x-prefixed hexadecimal identifier."
      )
    }
    return value
  }

  static func finiteDouble(_ raw: String, option: String) throws -> Double {
    guard let value = Double(raw), value.isFinite else {
      throw MappingCommandError.invalidArguments("\(option) must be a finite number.")
    }
    return value
  }
}
