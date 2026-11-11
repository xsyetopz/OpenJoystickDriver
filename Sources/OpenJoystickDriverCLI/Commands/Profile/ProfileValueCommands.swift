import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// One JSON value in a profile file, for `ojd profile get` and `ojd profile set`.
indirect enum ProfileValue: Codable, Equatable {
  /// JSON `null`.
  case null
  /// A JSON boolean.
  case bool(Bool)
  /// A JSON number without a fraction.
  case integer(Int64)
  /// A JSON number with a fraction.
  case number(Double)
  /// A JSON string.
  case string(String)
  /// A JSON array.
  case array([Self])
  /// A JSON object.
  case object([String: Self])

  /// Decodes a JSON value of any type.
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

  /// Encodes the value as plain JSON.
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

  /// The profile as a JSON tree.
  ///
  /// - Throws: The error of ``RemappingProfile/validate()``, or what the encoder or decoder throws.
  init(_ profile: RemappingProfile) throws {
    try profile.validate()
    self = try JSONDecoder().decode(Self.self, from: JSONEncoder().encode(profile))
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

  /// The value at `key`, a path of member names and array indexes, or nil when there is none.
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
  /// The argument as typed.
  let text: String
  /// The member names and array indexes.
  let components: [String]

  /// Parses `argument`; fails when a component is empty.
  init?(argument: String) {
    let components = argument.split(separator: ".", omittingEmptySubsequences: false)
      .map(String.init)
    guard !components.contains(where: \.isEmpty) else { return nil }
    text = argument
    self.components = components
  }
}

/// The shared help of the `KEY` argument.
private let profileKeyHelp = ArgumentHelp(
  CLILocalized.text(
    "cli.profile.group.key"
  ),
  valueName: "key"
)

/// The `ojd profile get` command: prints one value from a profile file.
///
/// A string prints alone, and any other value prints as JSON. A key with no value exits 1.
struct ProfileGetCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "get",
    abstract: CLILocalized.text("cli.profile.get.abstract"),
    discussion: CLILocalized.text(
      "cli.profile.get.discussion"
    )
  )

  /// The `--json` result.
  struct Result: Encodable, Equatable {
    /// The key as typed.
    let key: String
    /// The value at the key.
    let value: ProfileValue
  }

  /// The profile to read.
  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  /// The key of the value.
  @Argument(help: profileKeyHelp)
  var key: ProfileKey

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
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

/// The `ojd profile set` command: changes one value in a profile file.
///
/// The value is read as JSON, or as a string when it is not JSON. The whole profile must stay
/// valid.
struct ProfileSetCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "set",
    abstract: CLILocalized.text("cli.profile.set.abstract"),
    discussion: CLILocalized.text(
      "cli.profile.set.discussion"
    ) + "\n\n" + CLILocalized.text("cli.profile.set.examples")
  )

  /// The profile to change.
  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  /// The key of the value.
  @Argument(help: profileKeyHelp)
  var key: ProfileKey

  /// The value as JSON text.
  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.profile.set.value"),
      valueName: "value"
    )
  )
  var value: String

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
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
          message: CLILocalized.text("cli.profile.edit.unchanged")
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
          key.text,
          edited.name
        )
      )
    }
  }

  /// `profile` with `value` at `key`, checked by the strict decoder.
  ///
  /// - Throws: ``CLIFailure`` with the usage code when the key has no parent or the result is not a
  ///   valid profile.
  static func change(
    _ profile: RemappingProfile,
    key: ProfileKey,
    to value: ProfileValue
  ) throws -> RemappingProfile {
    guard let tree = try ProfileValue(profile).setting(value, at: key.components[...]) else {
      throw CLIFailure.usage(
        CLILocalized.format(
          "cli.profile.set.missing",
          profile.name,
          key.text
        )
      )
    }
    let edited: RemappingProfile
    do { edited = try RemappingProfileFileStore.load(from: try DocumentCoder.encode(tree)) } catch {
      throw CLIFailure(
        RemappingProfileFileStore.problemCode(error),
        CLILocalized.format(
          "cli.profile.set.invalid",
          key.text,
          DocumentProblem.describe(error)
        )
      )
    }
    guard edited.id == profile.id else {
      throw CLIFailure.usage(
        CLILocalized.text(
          "cli.profile.set.idChanged"
        )
      )
    }
    return try edited.checkingPointerSpeedDriver()
  }
}
