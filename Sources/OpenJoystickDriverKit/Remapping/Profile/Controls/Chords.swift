import Foundation

/// How a chord decides that its sources are pressed together.
public enum RemappingChordMode: String, Codable, Hashable, Sendable, CaseIterable {
  /// Fires as soon as every source is active and holds the sources' own bindings back.
  case modifier = "Modifier"
  /// Fires when every source is pressed within ``RemappingChord/windowMs`` of the first press.
  case simultaneous = "Simultaneous"
}

/// A multi-button combination that fires a single destination.
public struct RemappingChord: Codable, Equatable, Hashable, Identifiable, Sendable {
  /// Allowed range of ``windowMs``.
  public static let windowRange = 1.0...1000.0
  /// Stable identity of the chord inside its profile.
  public let id: UUID
  /// All sources that must be active simultaneously.
  public let sources: Set<RemappingSource>
  /// Output that the chord drives while it is active.
  public let destination: RemappingDestination
  /// How the chord decides that its sources are pressed together.
  public let mode: RemappingChordMode
  /// Longest time between the first and the last press of a ``RemappingChordMode/simultaneous``
  /// chord, in milliseconds.
  public let windowMs: Double

  /// Creates a chord.
  public init(
    id: UUID = UUID(),
    sources: Set<RemappingSource>,
    destination: RemappingDestination,
    mode: RemappingChordMode = .modifier,
    windowMs: Double = 50
  ) {
    self.id = id
    self.sources = sources
    self.destination = destination
    self.mode = mode
    self.windowMs = windowMs
  }

  /// Profile document keys of a chord.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    /// The JSON key of `id`.
    case id
    /// The JSON key of `sources`.
    case sources
    /// The JSON key of `destination`.
    case destination
    /// The JSON key of `mode`.
    case mode
    /// The JSON key of `windowMs`.
    case windowMs
  }

  /// Decodes a chord from a profile document; omitted mode and window take their defaults.
  /// - Throws: `DecodingError` for an unknown key, a missing key or a bad value.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    sources = try values.decode(Set<RemappingSource>.self, forKey: .sources)
    destination = try values.decode(RemappingDestination.self, forKey: .destination)
    mode = try values.decodeIfPresent(RemappingChordMode.self, forKey: .mode) ?? .modifier
    windowMs = try values.decodeIfPresent(Double.self, forKey: .windowMs) ?? 50
  }

  /// Encodes a chord and leaves out the mode and window that hold their default.
  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(id, forKey: .id)
    try values.encode(sources, forKey: .sources)
    try values.encode(destination, forKey: .destination)
    if mode != .modifier { try values.encode(mode, forKey: .mode) }
    if mode == .simultaneous || windowMs != 50 { try values.encode(windowMs, forKey: .windowMs) }
  }
}

/// An ordered multi-button sequence that fires a destination when completed in order within a
/// window.
public struct RemappingSequence: Codable, Equatable, Hashable, Identifiable, Sendable {
  /// Allowed range of ``windowMs``.
  public static let windowRange = 200.0...10000.0

  /// Stable identity of the sequence inside its profile.
  public let id: UUID
  /// Ordered sources that must be pressed in sequence.
  public let sources: [RemappingSource]
  /// Completion window in milliseconds (200...10000).
  public let windowMs: Double
  /// Output that is pressed and released when the sequence completes.
  public let destination: RemappingDestination

  /// Creates a sequence.
  public init(
    id: UUID = UUID(),
    sources: [RemappingSource],
    windowMs: Double,
    destination: RemappingDestination
  ) {
    self.id = id
    self.sources = sources
    self.windowMs = windowMs
    self.destination = destination
  }

  /// Profile document keys of a sequence.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    /// The JSON key of `id`.
    case id
    /// The JSON key of `sources`.
    case sources
    /// The JSON key of `windowMs`.
    case windowMs
    /// The JSON key of `destination`.
    case destination
  }

  /// Decodes a sequence from a profile document, which must give every field.
  /// - Throws: `DecodingError` for an unknown key, a missing key or a bad value.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    sources = try values.decode([RemappingSource].self, forKey: .sources)
    windowMs = try values.decode(Double.self, forKey: .windowMs)
    destination = try values.decode(RemappingDestination.self, forKey: .destination)
  }
}
