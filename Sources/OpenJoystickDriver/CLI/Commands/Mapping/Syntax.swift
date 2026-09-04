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
        throw MappingCommandError.invalidArguments(
          CLILocalized.format(
            "cli.mapping.unexpected_argument",
            "Unexpected argument '%@'.",
            option
          )
        )
      }
      guard values[option] == nil else {
        throw MappingCommandError.invalidArguments(
          CLILocalized.format("cli.mapping.option_repeated", "Option '%@' was repeated.", option)
        )
      }
      if flags.contains(option) {
        values[option] = "true"
        index += 1
      } else {
        guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
          throw MappingCommandError.invalidArguments(
            CLILocalized.format("cli.mapping.option_value_required", "%@ requires a value.", option)
          )
        }
        values[option] = arguments[index + 1]
        index += 2
      }
    }
  }

  func validate(allowed: Set<String>) throws {
    if let unknown = values.keys.sorted().first(where: { !allowed.contains($0) }) {
      throw MappingCommandError.invalidArguments(
        CLILocalized.format("cli.mapping.unknown_option", "Unknown option '%@'.", unknown)
      )
    }
  }

  func required(_ option: String) throws -> String {
    guard let value = values[option] else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.format("cli.mapping.option_required", "%@ is required.", option)
      )
    }
    return value
  }

  subscript(_ option: String) -> String? { values[option] }
  func contains(_ option: String) -> Bool { values[option] != nil }
}

enum MappingSyntax {
  static func source(_ raw: String) throws -> RemappingSource {
    do { return try RemappingCommandValueParser.source(raw) } catch {
      throw MappingCommandError.invalidArguments(
        CLILocalized.format("cli.mapping.value_invalid", "%@", error.localizedDescription)
      )
    }
  }

  static func destination(_ raw: String) throws -> RemappingDestination {
    do { return try RemappingCommandValueParser.destination(raw) } catch {
      throw MappingCommandError.invalidArguments(
        CLILocalized.format("cli.mapping.value_invalid", "%@", error.localizedDescription)
      )
    }
  }

  static func identifier(_ raw: String, option: String) throws -> UInt16 {
    let value = raw.lowercased().hasPrefix("0x") ? UInt16(raw.dropFirst(2), radix: 16) : UInt16(raw)
    guard let value else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.format(
          "cli.mapping.identifier_invalid",
          "%@ must be a 16-bit decimal or 0x-prefixed hexadecimal identifier.",
          option
        )
      )
    }
    return value
  }

  static func finiteDouble(_ raw: String, option: String) throws -> Double {
    guard let value = Double(raw), value.isFinite else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.format("cli.mapping.number_invalid", "%@ must be a finite number.", option)
      )
    }
    return value
  }

  static func sourceList(_ raw: String) throws -> [RemappingSource] {
    let entries = raw.split(separator: ",").map(String.init)
    guard !entries.isEmpty else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text(
          "cli.mapping.sources_required",
          "--sources requires at least one source."
        )
      )
    }
    return try entries.map { try source($0) }
  }

  static func uuid(_ raw: String, option: String) throws -> UUID {
    guard let id = UUID(uuidString: raw) else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.format("cli.mapping.uuid_invalid", "%@ must be a valid UUID.", option)
      )
    }
    return id
  }
}
