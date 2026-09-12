import Foundation

public enum RemappingChordMode: String, Codable, Hashable, Sendable, CaseIterable {
  case modifier
  case simultaneous
}

/// A multi-button combination that fires a single destination.
public struct RemappingChord: Codable, Equatable, Hashable, Identifiable, Sendable {
  public static let windowRange = 1.0...1000.0
  public let id: UUID
  /// All sources that must be active simultaneously.
  public let sources: Set<RemappingSource>
  public let destination: RemappingDestination
  public let mode: RemappingChordMode
  public let windowMs: Double

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

  private enum CodingKeys: String, CodingKey {
    case id
    case sources
    case destination
    case mode
    case windowMs = "window_ms"
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    sources = try values.decode(Set<RemappingSource>.self, forKey: .sources)
    destination = try values.decode(RemappingDestination.self, forKey: .destination)
    mode = try values.decodeIfPresent(RemappingChordMode.self, forKey: .mode) ?? .modifier
    windowMs = try values.decodeIfPresent(Double.self, forKey: .windowMs) ?? 50
  }

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
  public static let windowRange = 200.0...10000.0

  public let id: UUID
  /// Ordered sources that must be pressed in sequence.
  public let sources: [RemappingSource]
  /// Completion window in milliseconds (200...10000).
  public let windowMs: Double
  public let destination: RemappingDestination

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

  private enum CodingKeys: String, CodingKey {
    case id
    case sources
    case windowMs = "window_ms"
    case destination
  }
}
