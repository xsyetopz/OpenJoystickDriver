public import Foundation

/// How a binding drives its destination from its source.
public enum RemappingBindingBehavior: String, Codable, CaseIterable, Hashable, Sendable {
  /// The destination is down while the source is active.
  case hold = "Hold"
  /// Each activation of the source switches the destination between down and up.
  case toggle = "Toggle"
  /// A press and release of the destination when the source activates.
  case tapOnPress = "TapOnPress"
  /// A press and release of the destination when the source deactivates, if it was activated.
  case tapOnRelease = "TapOnRelease"
  /// The destination goes down on activation and up after ``RemappingBinding/pulseDurationMs``.
  case pulse = "Pulse"
  /// The destination goes down on activation and stays down.
  case press = "Press"
  /// Releases the held outputs of the destination on activation.
  case release = "Release"
}

/// Assigns one controller source to one destination, with timing, tuning and extra actions.
public struct RemappingBinding: Codable, Equatable, Hashable, Identifiable, Sendable {
  /// Allowed range of ``pulseDurationMs``.
  public static let pulseDurationRange = 1.0...5000.0
  /// ``pulseDurationMs`` used when none is given.
  public static let defaultPulseDurationMs = 100.0
  /// Allowed length of a ``remark``, in characters.
  public static let remarkLengthRange = 1...200
  /// Stable identity of the binding inside its profile.
  public let id: UUID
  /// Controller input that triggers the binding.
  public let source: RemappingSource
  /// Output that the binding drives.
  public let destination: RemappingDestination
  /// How the source drives the destination.
  public let behavior: RemappingBindingBehavior
  /// Time the destination stays down for ``RemappingBindingBehavior/pulse``, in milliseconds.
  public let pulseDurationMs: Double
  /// Axis processing; required for an axis source and refused for any other source.
  public let axisTuning: RemappingAxisTuning?
  /// Repeat setting for a button destination while the source is held.
  public let turbo: RemappingTurbo?
  /// Alternate action when the source is held past a duration.
  public let longHold: RemappingLongHold?
  /// Alternate actions when the source is tapped several times in a row, by tap count.
  public let multiTap: [RemappingMultiTap]
  /// Further actions that the same source triggers.
  public let additionalActions: [RemappingAction]
  /// A note the user wrote about the binding, or `nil` for none.
  public let remark: String?

  /// Creates a binding.
  public init(
    id: UUID = UUID(),
    source: RemappingSource,
    destination: RemappingDestination,
    behavior: RemappingBindingBehavior = .hold,
    pulseDurationMs: Double = Self.defaultPulseDurationMs,
    axisTuning: RemappingAxisTuning? = nil,
    turbo: RemappingTurbo? = nil,
    longHold: RemappingLongHold? = nil,
    multiTap: [RemappingMultiTap] = [],
    additionalActions: [RemappingAction] = [],
    remark: String? = nil
  ) {
    self.id = id
    self.source = source
    self.destination = destination
    self.behavior = behavior
    self.pulseDurationMs = pulseDurationMs
    self.axisTuning = axisTuning
    self.turbo = turbo
    self.longHold = longHold
    self.multiTap = multiTap
    self.additionalActions = additionalActions
    self.remark = remark
  }

  /// Profile document keys of a binding.
  enum CodingKeys: String, CodingKey, CaseIterable {
    case id
    case source
    case destination
    case behavior
    case pulseDurationMs
    case axisTuning
    case turbo
    case longHold
    case multiTap
    case additionalActions
    case remark
  }

  /// Decodes a binding from a profile document; omitted behavior, pulse duration and additional
  /// actions take their defaults.
  /// - Throws: `DecodingError` for an unknown key, a missing key or a bad value.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    source = try container.decode(RemappingSource.self, forKey: .source)
    destination = try container.decode(RemappingDestination.self, forKey: .destination)
    behavior =
      try container.decodeIfPresent(RemappingBindingBehavior.self, forKey: .behavior) ?? .hold
    pulseDurationMs =
      try container.decodeIfPresent(Double.self, forKey: .pulseDurationMs)
      ?? Self.defaultPulseDurationMs
    axisTuning = try container.decodeIfPresent(RemappingAxisTuning.self, forKey: .axisTuning)
    turbo = try container.decodeIfPresent(RemappingTurbo.self, forKey: .turbo)
    longHold = try container.decodeIfPresent(RemappingLongHold.self, forKey: .longHold)
    multiTap =
      try container.decodeIfPresent([RemappingMultiTap].self, forKey: .multiTap) ?? []
    additionalActions =
      try container.decodeIfPresent([RemappingAction].self, forKey: .additionalActions) ?? []
    remark = try container.decodeIfPresent(String.self, forKey: .remark)
  }

  /// Encodes a binding and leaves out the fields that hold their default.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(source, forKey: .source)
    try container.encode(destination, forKey: .destination)
    if behavior != .hold { try container.encode(behavior, forKey: .behavior) }
    if pulseDurationMs != Self.defaultPulseDurationMs || behavior == .pulse {
      try container.encode(pulseDurationMs, forKey: .pulseDurationMs)
    }
    try container.encodeIfPresent(axisTuning, forKey: .axisTuning)
    try container.encodeIfPresent(turbo, forKey: .turbo)
    try container.encodeIfPresent(longHold, forKey: .longHold)
    if !multiTap.isEmpty { try container.encode(multiTap, forKey: .multiTap) }
    if !additionalActions.isEmpty {
      try container.encode(additionalActions, forKey: .additionalActions)
    }
    try container.encodeIfPresent(remark, forKey: .remark)
  }
}
