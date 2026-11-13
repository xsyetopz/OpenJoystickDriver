public import Foundation

/// How many passes of its steps a macro runs.
public enum RemappingMacroRepeat: Codable, Equatable, Hashable, Sendable {
  /// The step list runs this many times.
  case count(Int)
  /// The step list runs again until the source is released.
  case whileHeld

  /// Profile document value of ``whileHeld``.
  private static let whileHeldName = "WhileHeld"

  /// Decodes a repeat from a profile document: an integer, or the string `WhileHeld`.
  /// - Throws: `DecodingError` for any other value.
  public init(from decoder: any Decoder) throws {
    let value = try decoder.singleValueContainer()
    if let count = try? value.decode(Int.self) {
      self = .count(count)
    } else if try value.decode(String.self) == Self.whileHeldName {
      self = .whileHeld
    } else {
      throw DecodingError.dataCorruptedError(
        in: value,
        debugDescription: "A repeat is a count or \(Self.whileHeldName)."
      )
    }
  }

  /// Encodes the count as an integer and ``whileHeld`` as its string.
  public func encode(to encoder: any Encoder) throws {
    var value = encoder.singleValueContainer()
    switch self {
    case .count(let count): try value.encode(count)
    case .whileHeld: try value.encode(Self.whileHeldName)
    }
  }
}

/// What a macro does when its source is pressed while it runs.
public enum RemappingMacroWhileRunning: String, Codable, CaseIterable, Hashable, Sendable {
  /// The running pass continues and no second pass starts.
  case ignore = "Ignore"
  /// The running pass stops with its outputs released, and a new pass starts.
  case restart = "Restart"
}

/// One step of a macro.
public enum RemappingMacroStep: Codable, Equatable, Hashable, Sendable {
  /// Presses and releases a destination at once.
  case tap(RemappingDestination)
  /// Presses a destination and keeps it down until a release step or the end of the pass.
  case press(RemappingDestination)
  /// Releases a destination that a press step holds.
  case release(RemappingDestination)
  /// Presses the destinations, holds them for a time, then releases them in reverse order.
  case chord(destinations: [RemappingDestination], holdMs: Double)
  /// Waits before the next step.
  case wait(durationMs: Double)

  /// Destinations that the step presses or releases.
  var destinations: [RemappingDestination] {
    switch self {
    case .tap(let destination), .press(let destination), .release(let destination): [destination]
    case .chord(let destinations, _): destinations
    case .wait: []
    }
  }

  /// Value of the `type` field that selects the case in a profile document.
  private enum Kind: String, Codable {
    case tap = "Tap"
    case press = "Press"
    case release = "Release"
    case chord = "Chord"
    case wait = "Wait"

    /// Keys that a profile document may give for this case, which `type` selects.
    var fields: [CodingKeys] {
      switch self {
      case .tap, .press, .release: [.type, .destination]
      case .chord: [.type, .destinations, .holdMs]
      case .wait: [.type, .durationMs]
      }
    }
  }

  /// Profile document keys of a step, merged across all cases.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    case type
    case destination
    case destinations
    case holdMs
    case durationMs
  }

  /// Decodes a step from a profile document.
  ///
  /// The `type` field selects the case, and keys that belong to another case are rejected.
  /// - Throws: `DecodingError` for an unknown or misplaced key, a missing key or a bad value.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try values.decode(Kind.self, forKey: .type)
    try values.rejectKeys(otherThan: kind.fields)
    switch kind {
    case .tap: self = .tap(try values.decode(RemappingDestination.self, forKey: .destination))
    case .press: self = .press(try values.decode(RemappingDestination.self, forKey: .destination))
    case .release:
      self = .release(try values.decode(RemappingDestination.self, forKey: .destination))
    case .chord:
      self = .chord(
        destinations: try values.decode([RemappingDestination].self, forKey: .destinations),
        holdMs: try values.decode(Double.self, forKey: .holdMs)
      )
    case .wait: self = .wait(durationMs: try values.decode(Double.self, forKey: .durationMs))
    }
  }

  /// Encodes the case under its `type` value with only its own keys.
  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .tap(let destination):
      try values.encode(Kind.tap, forKey: .type)
      try values.encode(destination, forKey: .destination)
    case .press(let destination):
      try values.encode(Kind.press, forKey: .type)
      try values.encode(destination, forKey: .destination)
    case .release(let destination):
      try values.encode(Kind.release, forKey: .type)
      try values.encode(destination, forKey: .destination)
    case .chord(let destinations, let holdMs):
      try values.encode(Kind.chord, forKey: .type)
      try values.encode(destinations, forKey: .destinations)
      try values.encode(holdMs, forKey: .holdMs)
    case .wait(let durationMs):
      try values.encode(Kind.wait, forKey: .type)
      try values.encode(durationMs, forKey: .durationMs)
    }
  }
}

/// A named list of timed output steps that a `Macro` destination runs.
public struct RemappingMacro: Codable, Equatable, Hashable, Identifiable, Sendable {
  /// Largest number of macros in a profile.
  public static let maximumCount = 16
  /// Allowed length of a macro name, in characters.
  public static let nameLengthRange = 1...40
  /// Allowed number of steps.
  public static let stepCountRange = 1...32
  /// Allowed range of a repeat count.
  public static let repeatCountRange = 1...500
  /// Allowed range of a wait or a chord hold in milliseconds.
  public static let delayMsRange = 0.0...5000.0
  /// Longest run time of one pass in milliseconds.
  public static let maximumPassMs = 30_000.0
  /// Longest run time of a counted macro in milliseconds.
  public static let maximumRunMs = 300_000.0
  /// Shortest time from the start of a pass to the start of the next, in milliseconds.
  public static let minimumPassIntervalMs = 1.0

  /// Stable identity of the macro inside its profile; a `Macro` destination holds it.
  public let id: UUID
  /// Name shown to the user, unique in the profile.
  public let name: String
  /// Steps in the order they run.
  public let steps: [RemappingMacroStep]
  /// How many passes the macro runs.
  public let repeatMode: RemappingMacroRepeat
  /// What a press of the source does while the macro runs.
  public let whileRunning: RemappingMacroWhileRunning
  /// Whether releasing the source stops the macro.
  public let interruptOnRelease: Bool

  /// Creates a macro.
  public init(
    id: UUID = UUID(),
    name: String,
    steps: [RemappingMacroStep],
    repeatMode: RemappingMacroRepeat = .count(1),
    whileRunning: RemappingMacroWhileRunning = .ignore,
    interruptOnRelease: Bool = false
  ) {
    self.id = id
    self.name = name
    self.steps = steps
    self.repeatMode = repeatMode
    self.whileRunning = whileRunning
    self.interruptOnRelease = interruptOnRelease
  }

  /// Time of one pass: the sum of its waits and chord holds, in milliseconds.
  var passMs: Double {
    steps.reduce(0) { total, step in
      switch step {
      case .wait(let durationMs): total + durationMs
      case .chord(_, let holdMs): total + holdMs
      case .tap, .press, .release: total
      }
    }
  }

  /// Profile document keys of a macro.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id
    case name
    case steps
    /// The JSON key of `repeat`, which holds ``repeatMode``.
    case repeatMode = "repeat"
    case whileRunning
    case interruptOnRelease
  }

  /// Decodes a macro from a profile document, which must give every field.
  /// - Throws: `DecodingError` for an unknown key, a missing key or a bad value.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    name = try values.decode(String.self, forKey: .name)
    steps = try values.decode([RemappingMacroStep].self, forKey: .steps)
    repeatMode = try values.decode(RemappingMacroRepeat.self, forKey: .repeatMode)
    whileRunning = try values.decode(RemappingMacroWhileRunning.self, forKey: .whileRunning)
    interruptOnRelease = try values.decode(Bool.self, forKey: .interruptOnRelease)
  }
}
