import Foundation

public enum RemappingGyroTrackballAxes: String, Codable, CaseIterable, Sendable {
  case pitch
  case yaw
  case both
}

/// Holds the selected angular velocities while the source is pressed.
public struct RemappingGyroTrackball: Codable, Equatable, Sendable {
  public let source: RemappingSource
  public let axes: RemappingGyroTrackballAxes
  /// Zero retains constant velocity; one halves velocity each second.
  public let decayHalvingsPerSecond: Double
  public let consumesSource: Bool

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

  public func validate() throws {
    if case .axis = source {
      throw RemappingGyroOutputError.invalidField("trackball.source")
    }
    guard decayHalvingsPerSecond.isFinite, (0...1000).contains(decayHalvingsPerSecond) else {
      throw RemappingGyroOutputError.invalidField("trackball.decay_halvings_per_second")
    }
  }

  private enum CodingKeys: String, CodingKey {
    case source, axes
    case decayHalvingsPerSecond = "decay_halvings_per_second"
    case consumesSource = "consumes_source"
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      source: try values.decode(RemappingSource.self, forKey: .source),
      axes: try values.decodeIfPresent(RemappingGyroTrackballAxes.self, forKey: .axes) ?? .both,
      decayHalvingsPerSecond: try values.decodeIfPresent(
        Double.self, forKey: .decayHalvingsPerSecond
      ) ?? 1,
      consumesSource: try values.decodeIfPresent(Bool.self, forKey: .consumesSource) ?? true
    )
    try validate()
  }
}
