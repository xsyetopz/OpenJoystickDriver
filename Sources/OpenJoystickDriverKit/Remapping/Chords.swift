import Foundation

/// A simultaneous multi-button combination that fires a single destination.
public struct RemappingChord: Codable, Equatable, Hashable, Identifiable, Sendable {
  public let id: UUID
  /// All sources that must be active simultaneously.
  public let sources: Set<RemappingSource>
  public let destination: RemappingDestination

  public init(id: UUID = UUID(), sources: Set<RemappingSource>, destination: RemappingDestination) {
    self.id = id
    self.sources = sources
    self.destination = destination
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case sources
    case destination
  }
}

/// An ordered multi-button sequence that fires a destination when completed in order within a window.
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
