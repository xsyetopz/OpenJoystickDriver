import Foundation

/// An independently owned output action within a control assignment.
public struct RemappingAction: Codable, Equatable, Hashable, Identifiable, Sendable {
  /// Stable identity of the action inside its profile.
  public let id: UUID
  /// Output that the action drives.
  public let destination: RemappingDestination
  /// How the source drives the destination.
  public let behavior: RemappingBindingBehavior
  /// Time the destination stays down for ``RemappingBindingBehavior/pulse``, in milliseconds.
  public let pulseDurationMs: Double
  /// Repeat setting for a button destination while the source is held.
  public let turbo: RemappingTurbo?
  /// Alternate action when the source is held past a duration.
  public let longHold: RemappingLongHold?
  /// Alternate actions when the source is tapped several times in a row, by tap count.
  public let multiTap: [RemappingMultiTap]

  /// Creates an action.
  public init(
    id: UUID = UUID(),
    destination: RemappingDestination,
    behavior: RemappingBindingBehavior = .hold,
    pulseDurationMs: Double = RemappingBinding.defaultPulseDurationMs,
    turbo: RemappingTurbo? = nil,
    longHold: RemappingLongHold? = nil,
    multiTap: [RemappingMultiTap] = []
  ) {
    self.id = id
    self.destination = destination
    self.behavior = behavior
    self.pulseDurationMs = pulseDurationMs
    self.turbo = turbo
    self.longHold = longHold
    self.multiTap = multiTap
  }

  /// Profile document keys of an action.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    /// The JSON key of `id`.
    case id
    /// The JSON key of `destination`.
    case destination
    /// The JSON key of `behavior`.
    case behavior
    /// The JSON key of `turbo`.
    case turbo
    /// The JSON key of `pulseDurationMs`.
    case pulseDurationMs
    /// The JSON key of `longHold`.
    case longHold
    /// The JSON key of `multiTap`.
    case multiTap
  }

  /// Decodes an action from a profile document; omitted behavior and pulse duration take their
  /// defaults.
  /// - Throws: `DecodingError` for an unknown key, a missing key or a bad value.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    destination = try values.decode(RemappingDestination.self, forKey: .destination)
    behavior = try values.decodeIfPresent(RemappingBindingBehavior.self, forKey: .behavior) ?? .hold
    pulseDurationMs =
      try values.decodeIfPresent(Double.self, forKey: .pulseDurationMs)
      ?? RemappingBinding.defaultPulseDurationMs
    turbo = try values.decodeIfPresent(RemappingTurbo.self, forKey: .turbo)
    longHold = try values.decodeIfPresent(RemappingLongHold.self, forKey: .longHold)
    multiTap =
      try values.decodeIfPresent([RemappingMultiTap].self, forKey: .multiTap) ?? []
  }

  /// Encodes an action and leaves out the fields that hold their default.
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
    if !multiTap.isEmpty { try values.encode(multiTap, forKey: .multiTap) }
  }

  /// Returns the action as a binding of the given source and axis tuning.
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
      multiTap: multiTap
    )
  }
}
