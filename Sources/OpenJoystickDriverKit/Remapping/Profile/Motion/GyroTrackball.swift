import Foundation

/// Axes of gyro motion that a trackball holds.
public enum RemappingGyroTrackballAxes: String, Codable, CaseIterable, Sendable {
  /// Holds pitch only.
  case pitch = "Pitch"
  /// Holds yaw only.
  case yaw = "Yaw"
  /// Holds pitch and yaw.
  case both = "Both"
}

/// Holds the selected angular velocities while the source is pressed.
public struct RemappingGyroTrackball: Codable, Equatable, Sendable {
  /// Source whose press holds the velocity.
  public let source: RemappingSource
  /// Axes that are held.
  public let axes: RemappingGyroTrackballAxes
  /// Zero retains constant velocity; one halves velocity each second.
  public let decayHalvingsPerSecond: Double
  /// Keeps the source out of passthrough output.
  public let consumesSource: Bool

  /// Creates a gyro trackball.
  public init(
    source: RemappingSource,
    axes: RemappingGyroTrackballAxes = .both,
    decayHalvingsPerSecond: Double = 1,
    consumesSource: Bool = true
  ) {
    self.source = source
    self.axes = axes
    self.decayHalvingsPerSecond = decayHalvingsPerSecond
    self.consumesSource = consumesSource
  }

  /// Checks that the source is not an analog axis and that the decay is finite and within 0 to
  /// 1000.
  /// - Throws: ``RemappingGyroOutputError/invalidField(_:)`` with the dotted snake_case field name.
  public func validate() throws {
    if case .axis = source { throw RemappingGyroOutputError.invalidField("trackball.source") }
    guard decayHalvingsPerSecond.isFinite, (0...1000).contains(decayHalvingsPerSecond) else {
      throw RemappingGyroOutputError.invalidField("trackball.decay_halvings_per_second")
    }
  }

  /// Profile document keys of a gyro trackball.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    /// The JSON key of `source`.
    case source
    /// The JSON key of `axes`.
    case axes
    /// The JSON key of `decayHalvingsPerSecond`.
    case decayHalvingsPerSecond
    /// The JSON key of `consumesSource`.
    case consumesSource
  }

  /// Decodes a gyro trackball from a profile document.
  ///
  /// Omitted fields take the initializer defaults.
  /// - Throws: `DecodingError` for an unknown key or a bad value, or the error of ``validate()``.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      source: try values.decode(RemappingSource.self, forKey: .source),
      axes: try values.decodeIfPresent(RemappingGyroTrackballAxes.self, forKey: .axes) ?? .both,
      decayHalvingsPerSecond: try values.decodeIfPresent(
        Double.self,
        forKey: .decayHalvingsPerSecond
      ) ?? 1,
      consumesSource: try values.decodeIfPresent(Bool.self, forKey: .consumesSource) ?? true
    )
    try validate()
  }
}
