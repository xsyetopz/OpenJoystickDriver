import Foundation

/// How a `LayerSet` or `Pause` destination changes its state.
public enum RemappingSwitchMode: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  /// Turns the state on.
  case on = "On"
  /// Turns the state off.
  case off = "Off"
  /// Flips the state.
  case toggle = "Toggle"

  /// The state after this mode applies to `current`.
  func apply(to current: Bool) -> Bool {
    switch self {
    case .on: true
    case .off: false
    case .toggle: !current
    }
  }
}

/// The profile that a `ProfileSwitch` destination activates.
///
/// A profile document holds it as one string: a profile identifier, `Next` or `Previous`.
public enum RemappingProfileTarget: Codable, Equatable, Hashable, Sendable {
  /// The profile with this identifier.
  case profile(UUID)
  /// The next profile of the same model and scope in case-insensitive name order, wrapping.
  case next
  /// The previous profile of the same model and scope in case-insensitive name order, wrapping.
  case previous

  /// Decodes `Next`, `Previous` or a profile identifier.
  /// - Throws: `DecodingError` for another string.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let text = try container.decode(String.self)
    switch text {
    case "Next": self = .next
    case "Previous": self = .previous
    default:
      guard let id = UUID(uuidString: text) else {
        throw DecodingError.dataCorruptedError(
          in: container,
          debugDescription: "Expected Next, Previous or a profile identifier."
        )
      }
      self = .profile(id)
    }
  }

  /// Encodes the target as its string.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .next: try container.encode("Next")
    case .previous: try container.encode("Previous")
    case .profile(let id): try container.encode(id.uuidString)
    }
  }

  /// Returns the profile to activate when `current` is active among `profiles`.
  ///
  /// `profiles` are those of the current profile's model and scope. `Next` and `Previous` walk
  /// them in case-insensitive name order, ties by identifier, and wrap. The result is `nil` when
  /// a named profile is not among them or `current` is not.
  public func resolve(from current: UUID, among profiles: [RemappingProfile]) -> RemappingProfile? {
    if case .profile(let id) = self { return profiles.first { $0.id == id } }
    let ordered = profiles.sorted {
      let order = $0.name.caseInsensitiveCompare($1.name)
      return order == .orderedSame
        ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
    }
    guard let index = ordered.firstIndex(where: { $0.id == current }) else { return nil }
    let offset = self == .next ? 1 : ordered.count - 1
    return ordered[(index + offset) % ordered.count]
  }
}

extension RemappingDestination {
  /// Whether the destination is a `ProfileSwitch`, `LayerSet` or `Pause`, which fire on a press.
  var isProfileControl: Bool {
    switch self {
    case .profileSwitch, .layerSet, .pause: true
    default: false
    }
  }

  /// Whether the destination is a `Pause`.
  var isPause: Bool {
    if case .pause = self { return true }
    return false
  }
}

extension RemappingDestination {
  /// Whether the destination is a `Speak`.
  var isSpeak: Bool {
    if case .speak = self { return true }
    return false
  }
}

extension RemappingProfile {
  /// The longest `Speak` text, in Unicode scalars.
  static let maximumSpeechCharacters = 128

  /// Checks that this Mac has every voice that a `Speak` destination names.
  /// - Throws: ``RemappingValidationError/unknownSpeechVoice(_:)``.
  public func validateSpeechVoices(using speech: any RemappingSpeechOutput) throws {
    for voice in speechVoices where !speech.hasVoice(voice) {
      throw RemappingValidationError.unknownSpeechVoice(voice)
    }
  }

  /// Checks that every `ProfileSwitch` names a profile among `profiles` for the same model.
  ///
  /// `Next` and `Previous` need no check.
  /// - Throws: ``RemappingValidationError``.
  public func validateProfileSwitches(among profiles: [RemappingProfile]) throws {
    for case .profile(let id) in profileSwitchTargets {
      guard let target = profiles.first(where: { $0.id == id }) else {
        throw RemappingValidationError.unknownSwitchProfile(id)
      }
      guard target.device.vendorID == device.vendorID, target.device.productID == device.productID
      else { throw RemappingValidationError.switchProfileForOtherModel(id) }
    }
  }
}
