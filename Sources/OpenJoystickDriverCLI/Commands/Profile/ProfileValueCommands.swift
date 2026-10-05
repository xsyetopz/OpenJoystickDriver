import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// One JSON value in a profile file, for `ojd profile get` and `ojd profile set`.
indirect enum ProfileValue: Codable, Equatable {
  case null
  case bool(Bool)
  case integer(Int64)
  case number(Double)
  case string(String)
  case array([Self])
  case object([String: Self])

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int64.self) {
      self = .integer(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([Self].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: Self].self))
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .integer(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    }
  }

  /// The profile as the JSON tree that `ojd profile export` writes.
  init(_ profile: RemappingProfile) throws {
    let text = try RemappingProfileFileStore.encodedJSON(profile)
    self = try JSONDecoder().decode(Self.self, from: Data(text.utf8))
  }

  /// `text` read as JSON, or as a string when it is not JSON.
  init(argument text: String) {
    self = (try? JSONDecoder().decode(Self.self, from: Data(text.utf8))) ?? .string(text)
  }

  /// A string alone, and any other value as one line of JSON.
  var text: String {
    if case .string(let value) = self { return value }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return (try? encoder.encode(self)).flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
  }

  func value(at key: ArraySlice<String>) -> Self? {
    guard let first = key.first else { return self }
    switch self {
    case .object(let members): return members[first]?.value(at: key.dropFirst())
    case .array(let items):
      guard let index = Int(first), items.indices.contains(index) else { return nil }
      return items[index].value(at: key.dropFirst())
    default: return nil
    }
  }

  /// This value with `value` at `key`, or nil when `key` has no parent.
  ///
  /// `null` removes an object member or an array item, and the index one past the end of an
  /// array adds an item.
  func setting(_ value: Self, at key: ArraySlice<String>) -> Self? {
    guard let first = key.first else { return value }
    let last = key.count == 1
    switch self {
    case .object(var members):
      if last {
        members[first] = value == .null ? nil : value
      } else {
        guard let child = members[first]?.setting(value, at: key.dropFirst()) else { return nil }
        members[first] = child
      }
      return .object(members)
    case .array(var items):
      guard let index = Int(first), index >= 0 else { return nil }
      if last, index == items.count, value != .null {
        items.append(value)
      } else {
        guard items.indices.contains(index) else { return nil }
        if last, value == .null {
          items.remove(at: index)
        } else {
          guard let child = items[index].setting(value, at: key.dropFirst()) else { return nil }
          items[index] = child
        }
      }
      return .array(items)
    default: return nil
    }
  }
}

/// The `KEY` argument: member names and array indexes joined by dots.
struct ProfileKey: ExpressibleByArgument, Equatable, Sendable {
  let text: String
  let components: [String]

  init?(argument: String) {
    let components = argument.split(separator: ".", omittingEmptySubsequences: false)
      .map(String.init)
    guard !components.contains(where: \.isEmpty) else { return nil }
    text = argument
    self.components = components
  }
}

private let profileKeyHelp = ArgumentHelp(
  CLILocalized.text(
    "cli.profile.key",
    "The key: names and array indexes joined by dots, such as bindings.0.behavior."
  ),
  valueName: "key"
)

struct ProfileGetCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "get",
    abstract: CLILocalized.text("cli.profile.get.abstract", "Print one value from a profile."),
    discussion: CLILocalized.text(
      "cli.profile.get.discussion",
      "KEY is a path into the profile file that 'ojd profile export' prints, such as "
        + "stickMappings.0.tuning.innerDeadzone. Prints a string alone and any other value as "
        + "JSON. With --json, prints the key and the value."
    )
  )

  /// The `--json` result.
  struct Result: Encodable, Equatable {
    let key: String
    let value: ProfileValue
  }

  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  @Argument(help: profileKeyHelp)
  var key: ProfileKey

  @OptionGroup
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let selector = profile
      let (document, _) = try await ServiceConnection.request {
        try await selector.resolve(with: $0)
      }
      guard let value = try ProfileValue(document).value(at: key.components[...]) else {
        throw CLIFailure(
          .notFound,
          CLILocalized.format(
            "cli.profile.get.missing",
            "'%@' has no value at %@.",
            document.name,
            key.text
          )
        )
      }
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(Result(key: key.text, value: value))
      case .plain, .human: CLIOutput.stdout(value.text)
      }
    }
  }
}

struct ProfileSetCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "set",
    abstract: CLILocalized.text("cli.profile.set.abstract", "Change one value in a profile."),
    discussion: CLILocalized.text(
      "cli.profile.set.discussion",
      "KEY is a path into the profile file, as in 'ojd profile get'. VALUE is read as JSON, or "
        + "as a string when it is not JSON, so 0.2 is a number and space is a string. null "
        + "removes the key or the array item, and the index one past the end of an array adds "
        + "an item. The whole profile is checked before it is saved, and the ID cannot change."
    )
  )

  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  @Argument(help: profileKeyHelp)
  var key: ProfileKey

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.profile.set.value", "The new value, as JSON or as a string."),
      valueName: "value"
    )
  )
  var value: String

  @OptionGroup
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let selector = profile
      let (current, snapshot) = try await ServiceConnection.request {
        try await selector.resolve(with: $0)
      }
      let edited = try Self.change(current, key: key, to: ProfileValue(argument: value))
      guard edited != current else {
        try printProfile(
          ProfileResult(profile: ProfileSummary(current, snapshot: snapshot), changed: false),
          message: CLILocalized.text("cli.profile.edit.unchanged", "Nothing changed.")
        )
        return
      }
      let after = try await ServiceConnection.request {
        try await $0.updateRemappingProfile(edited, expectedCurrent: current)
      }
      try printProfile(
        ProfileResult(profile: try savedSummary(edited.id, in: after), changed: true),
        message: CLILocalized.format(
          "cli.profile.set.done",
          "Set %@ in '%@'.",
          key.text,
          edited.name
        )
      )
    }
  }

  /// `profile` with `value` at `key`, checked by the strict decoder.
  static func change(
    _ profile: RemappingProfile,
    key: ProfileKey,
    to value: ProfileValue
  ) throws -> RemappingProfile {
    guard let tree = try ProfileValue(profile).setting(value, at: key.components[...]) else {
      throw CLIFailure.usage(
        CLILocalized.format(
          "cli.profile.set.missing",
          "'%@' has no place for %@. Set a key that exists, or set its parent to a whole value.",
          profile.name,
          key.text
        )
      )
    }
    let edited: RemappingProfile
    do { edited = try RemappingProfileFileStore.load(from: try JSONEncoder().encode(tree)) } catch {
      throw CLIFailure.usage(
        CLILocalized.format(
          "cli.profile.set.invalid",
          "Setting %@ makes the profile invalid: %@",
          key.text,
          DocumentProblem.describe(error)
        )
      )
    }
    guard edited.id == profile.id else {
      throw CLIFailure.usage(
        CLILocalized.text(
          "cli.profile.set.id_changed",
          "The profile ID cannot change. Use 'ojd profile duplicate' to make a copy."
        )
      )
    }
    return edited
  }
}
