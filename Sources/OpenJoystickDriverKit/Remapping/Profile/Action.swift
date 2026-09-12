import Foundation

/// An independently owned output action within a control assignment.
public struct RemappingAction: Codable, Equatable, Hashable, Identifiable, Sendable {
  public let id: UUID
  public let destination: RemappingDestination
  public let behavior: RemappingBindingBehavior
  public let pulseDurationMs: Double
  public let turbo: RemappingTurbo?
  public let longHold: RemappingLongHold?
  public let doubleTap: RemappingDoubleTap?

  public init(
    id: UUID = UUID(),
    destination: RemappingDestination,
    behavior: RemappingBindingBehavior = .hold,
    pulseDurationMs: Double = RemappingBinding.defaultPulseDurationMs,
    turbo: RemappingTurbo? = nil,
    longHold: RemappingLongHold? = nil,
    doubleTap: RemappingDoubleTap? = nil
  ) {
    self.id = id
    self.destination = destination
    self.behavior = behavior
    self.pulseDurationMs = pulseDurationMs
    self.turbo = turbo
    self.longHold = longHold
    self.doubleTap = doubleTap
  }

  private enum CodingKeys: String, CodingKey {
    case id, destination, behavior, turbo
    case pulseDurationMs = "pulse_duration_ms"
    case longHold = "long_hold"
    case doubleTap = "double_tap"
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    destination = try values.decode(RemappingDestination.self, forKey: .destination)
    behavior = try values.decodeIfPresent(RemappingBindingBehavior.self, forKey: .behavior) ?? .hold
    pulseDurationMs = try values.decodeIfPresent(Double.self, forKey: .pulseDurationMs)
      ?? RemappingBinding.defaultPulseDurationMs
    turbo = try values.decodeIfPresent(RemappingTurbo.self, forKey: .turbo)
    longHold = try values.decodeIfPresent(RemappingLongHold.self, forKey: .longHold)
    doubleTap = try values.decodeIfPresent(RemappingDoubleTap.self, forKey: .doubleTap)
  }

  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(id, forKey: .id)
    try values.encode(destination, forKey: .destination)
    if behavior != .hold { try values.encode(behavior, forKey: .behavior) }
    if behavior == .pulse || pulseDurationMs != RemappingBinding.defaultPulseDurationMs {
      try values.encode(pulseDurationMs, forKey: .pulseDurationMs)
    }
    try values.encodeIfPresent(turbo, forKey: .turbo)
    try values.encodeIfPresent(longHold, forKey: .longHold)
    try values.encodeIfPresent(doubleTap, forKey: .doubleTap)
  }

  func binding(source: RemappingSource, axisTuning: RemappingAxisTuning?) -> RemappingBinding {
    RemappingBinding(
      id: id,
      source: source,
      destination: destination,
      behavior: behavior,
      pulseDurationMs: pulseDurationMs,
      axisTuning: axisTuning,
      turbo: turbo,
      longHold: longHold,
      doubleTap: doubleTap
    )
  }
}
