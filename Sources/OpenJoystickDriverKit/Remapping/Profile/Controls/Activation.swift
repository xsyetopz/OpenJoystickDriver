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
    case durationMs
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

/// Alternate action fired when a button is tapped a given number of times in a row.
public struct RemappingMultiTap: Codable, Equatable, Hashable, Sendable {
  /// Allowed range of ``count``.
  public static let countRange = 2...5
  /// Allowed range of ``windowMs``.
  public static let windowRange = 50.0...1000.0

  /// Number of taps that fire the entry (2...5).
  public let count: Int
  /// Time from one tap's release to the next press in milliseconds (50...1000).
  public let windowMs: Double
  /// Output that the tap count drives.
  public let destination: RemappingDestination

  /// Creates a tap-count action.
  public init(count: Int, windowMs: Double, destination: RemappingDestination) {
    self.count = count
    self.windowMs = windowMs
    self.destination = destination
  }

  /// Profile document keys of a tap-count action.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    case count
    case windowMs
    case destination
  }

  /// Decodes a tap-count action from a profile document, which must give all fields.
  /// - Throws: `DecodingError` for an unknown key, a missing key or a bad value.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    count = try values.decode(Int.self, forKey: .count)
    windowMs = try values.decode(Double.self, forKey: .windowMs)
    destination = try values.decode(RemappingDestination.self, forKey: .destination)
  }
}

extension [RemappingMultiTap] {
  /// The longest window among the entries that need more than `taps` taps, or 0 for none.
  public func continuationWindowMs(after taps: Int) -> Double {
    filter { $0.count > taps }.map(\.windowMs).max() ?? 0
  }

  /// The longest window among all entries, or 0 for none.
  public var longestWindowMs: Double { continuationWindowMs(after: 0) }
}
