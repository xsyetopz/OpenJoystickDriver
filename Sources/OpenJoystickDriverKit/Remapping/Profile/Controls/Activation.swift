import Foundation

/// Alternate action fired when a button is held beyond a duration threshold.
public struct RemappingLongHold: Codable, Equatable, Hashable, Sendable {
  /// Allowed range of ``durationMs``.
  public static let durationRange = 100.0...5000.0

  /// Threshold in milliseconds (100...5000).
  public let durationMs: Double
  /// Output that the long hold drives.
  public let destination: RemappingDestination

  /// Creates a long-hold action.
  public init(durationMs: Double, destination: RemappingDestination) {
    self.durationMs = durationMs
    self.destination = destination
  }

  /// Profile document keys of a long-hold action.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    /// The JSON key of `durationMs`.
    case durationMs
    /// The JSON key of `destination`.
    case destination
  }

  /// Decodes a long-hold action from a profile document, which must give both fields.
  /// - Throws: `DecodingError` for an unknown key, a missing key or a bad value.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    durationMs = try values.decode(Double.self, forKey: .durationMs)
    destination = try values.decode(RemappingDestination.self, forKey: .destination)
  }
}

/// Alternate action fired when a button is pressed twice within a time window.
public struct RemappingDoubleTap: Codable, Equatable, Hashable, Sendable {
  /// Allowed range of ``windowMs``.
  public static let windowRange = 50.0...1000.0

  /// Double-tap window in milliseconds (50...1000).
  public let windowMs: Double
  /// Output that the double tap drives.
  public let destination: RemappingDestination

  /// Creates a double-tap action.
  public init(windowMs: Double, destination: RemappingDestination) {
    self.windowMs = windowMs
    self.destination = destination
  }

  /// Profile document keys of a double-tap action.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    /// The JSON key of `windowMs`.
    case windowMs
    /// The JSON key of `destination`.
    case destination
  }

  /// Decodes a double-tap action from a profile document, which must give both fields.
  /// - Throws: `DecodingError` for an unknown key, a missing key or a bad value.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    windowMs = try values.decode(Double.self, forKey: .windowMs)
    destination = try values.decode(RemappingDestination.self, forKey: .destination)
  }
}
