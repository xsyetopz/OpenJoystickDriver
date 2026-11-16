public import Foundation

/// How a layer is activated by its activator source.
public enum RemappingLayerActivation: String, Codable, Equatable, Hashable, Sendable {
  /// Active while the activator is held.
  case hold = "Hold"
  /// Toggled on/off on each activator press.
  case toggle = "Toggle"
}

/// An alternate mapping set activated by a designated button or dpad direction.
public struct RemappingLayer: Codable, Equatable, Hashable, Identifiable, Sendable {
  /// Stable identity of the layer inside its profile.
  public let id: UUID
  /// Name shown to the user.
  public let name: String
  /// How the activator turns the layer on.
  public let activationMode: RemappingLayerActivation
  /// Source that turns the layer on; it cannot also have a binding.
  public let activator: RemappingSource
  /// Bindings that replace the base binding of the same source while the layer is active.
  public let bindings: [RemappingBinding]
  /// Chords that replace the base chord of the same source set while the layer is active.
  public let chords: [RemappingChord]
  /// Sequences that apply in addition to the base sequences while the layer is active.
  public let sequences: [RemappingSequence]
  /// Motion tuning that replaces the profile's while the layer is active, or `nil` to keep it.
  public let motionTuning: RemappingMotionTuning?

  /// Creates a layer.
  public init(
    id: UUID = UUID(),
    name: String,
    activationMode: RemappingLayerActivation,
    activator: RemappingSource,
    bindings: [RemappingBinding] = [],
    chords: [RemappingChord] = [],
    sequences: [RemappingSequence] = [],
    motionTuning: RemappingMotionTuning? = nil
  ) {
    self.id = id
    self.name = name
    self.activationMode = activationMode
    self.activator = activator
    self.bindings = bindings
    self.chords = chords
    self.sequences = sequences
    self.motionTuning = motionTuning
  }

  /// Profile document keys of a layer.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id
    case name
    case activationMode
    case activator
    case bindings
    case chords
    case sequences
    case motionTuning
  }

  /// Decodes a layer from a profile document; every field except the motion tuning is required.
  /// - Throws: `DecodingError` for an unknown key, a missing key or a bad value.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    name = try values.decode(String.self, forKey: .name)
    activationMode = try values.decode(RemappingLayerActivation.self, forKey: .activationMode)
    activator = try values.decode(RemappingSource.self, forKey: .activator)
    bindings = try values.decode([RemappingBinding].self, forKey: .bindings)
    chords = try values.decode([RemappingChord].self, forKey: .chords)
    sequences = try values.decode([RemappingSequence].self, forKey: .sequences)
    motionTuning = try values.decodeIfPresent(RemappingMotionTuning.self, forKey: .motionTuning)
  }
}
