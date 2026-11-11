import Foundation

/// One JSON value in a profile file, for `ojd profile get` and `ojd profile set`.
public indirect enum ProfileValue: Codable, Equatable, Sendable {
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
  public init(from decoder: any Decoder) throws {
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
  public func encode(to encoder: any Encoder) throws {
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
  public init(_ profile: RemappingProfile) throws {
    try profile.validate()
    self = try JSONDecoder().decode(Self.self, from: JSONEncoder().encode(profile))
  }

  /// `text` read as JSON, or as a string when it is not JSON.
  public init(argument text: String) {
    self = (try? JSONDecoder().decode(Self.self, from: Data(text.utf8))) ?? .string(text)
  }

  /// A string alone, and any other value as one line of JSON.
  public var text: String {
    if case .string(let value) = self { return value }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return (try? encoder.encode(self)).flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
  }

  /// The value at `key`, a path of member names and array indexes, or nil when there is none.
  public func value(at key: ArraySlice<String>) -> Self? {
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
  public func setting(_ value: Self, at key: ArraySlice<String>) -> Self? {
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

/// A key into a profile: member names and array indexes joined by dots.
public struct ProfileKey: Equatable, Sendable {
  /// The key as typed.
  public let text: String
  /// The member names and array indexes.
  public let components: [String]

  /// Parses `argument`; fails when a component is empty.
  public init?(argument: String) {
    let parts = argument.split(separator: ".", omittingEmptySubsequences: false)
      .map(String.init)
    guard !parts.contains(where: \.isEmpty) else { return nil }
    text = argument
    self.components = parts
  }
}

/// A profile UUID, or a profile name matched exactly but without regard to case.
public struct ProfileSelector: Equatable, Sendable {
  /// The selector as typed.
  public let text: String

  /// Parses `argument`; fails when it is empty.
  public init?(argument: String) {
    guard !argument.isEmpty else { return nil }
    text = argument
  }

  /// The one profile this selector names.
  ///
  /// - Throws: ``CodedFailure`` with the not-found code when no profile or several profiles match.
  public func resolve(in profiles: [RemappingProfile]) throws -> RemappingProfile {
    if let id = UUID(uuidString: text), let profile = profiles.first(where: { $0.id == id }) {
      return profile
    }
    let matches = profiles.filter { $0.name.caseInsensitiveCompare(text) == .orderedSame }
    if matches.count == 1, let profile = matches.first { return profile }
    let localization = Localization()
    guard matches.isEmpty else {
      let message = localization.plural(
        "cli.profile.group.selectorAmbiguous",
        arguments: [text, matches.count]
      )
      let lines = matches.map { "  \($0.id.uuidString)  \($0.name)" }
      throw CodedFailure(.notFound, ([message] + lines).joined(separator: "\n"))
    }
    throw CodedFailure(
      .notFound,
      localization.formatted("cli.profile.group.selectorNotFound", arguments: [text])
    )
  }
}

extension RemappingProfile {
  /// Checks that the controller reports the trigger or stick of the pointer speed.
  ///
  /// The model has no capability data, so this runs where the profile enters: `profile set` and
  /// `profile import`. A controller that the catalog does not know is not checked.
  ///
  /// - Throws: ``CodedFailure`` with the invalid profile code when the controller lacks the driver.
  public func checkingPointerSpeedDriver() throws -> Self {
    if let speed = pointerSpeed,
      let capabilities = ProtocolDriverRegistry().profileCapabilities(
        for: ControllerModelID(vendorID: device.vendorID, productID: device.productID)
      ), !speed.isSupported(by: capabilities)
    {
      throw CodedFailure(
        .invalidProfile,
        Localization().formatted(
          "cli.profile.group.invalid",
          arguments: [RemappingValidationError.unsupportedPointerSpeedDriver.localizedDescription]
        )
      )
    }
    return self
  }
}

/// The edit that `ojd profile set`, the endpoint, and the App Intents share.
public enum ProfileSetting {
  /// `profile` with `value` at `key`, checked by the strict decoder.
  ///
  /// - Throws: ``CodedFailure`` with the usage code when the key has no parent or the ID changes,
  ///   and with the code of the problem when the result is not a valid profile.
  public static func change(
    _ profile: RemappingProfile,
    key: ProfileKey,
    to value: ProfileValue
  ) throws -> RemappingProfile {
    let localization = Localization()
    guard let tree = try ProfileValue(profile).setting(value, at: key.components[...]) else {
      throw CodedFailure.usage(
        localization.formatted("cli.profile.set.missing", arguments: [profile.name, key.text])
      )
    }
    let edited: RemappingProfile
    do { edited = try RemappingProfileFileStore.load(from: try DocumentCoder.encode(tree)) } catch {
      throw CodedFailure(
        RemappingProfileFileStore.problemCode(error),
        localization.formatted(
          "cli.profile.set.invalid",
          arguments: [key.text, DocumentProblem.describe(error)]
        )
      )
    }
    guard edited.id == profile.id else {
      throw CodedFailure.usage(localization.string("cli.profile.set.idChanged"))
    }
    return try edited.checkingPointerSpeedDriver()
  }
}
