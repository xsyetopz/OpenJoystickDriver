import Foundation

/// How a layer is activated by its activator source.
public enum RemappingLayerActivation: String, Codable, Equatable, Hashable, Sendable {
  /// Active while the activator is held.
  case hold
  /// Toggled on/off on each activator press.
  case toggle
}

/// An alternate mapping set activated by a designated button or dpad direction.
public struct RemappingLayer: Codable, Equatable, Hashable, Identifiable, Sendable {
  public let id: UUID
  public let name: String
  public let activationMode: RemappingLayerActivation
  public let activator: RemappingSource
  public let bindings: [RemappingBinding]
  public let chords: [RemappingChord]
  public let sequences: [RemappingSequence]

  public init(
    id: UUID = UUID(),
    name: String,
    activationMode: RemappingLayerActivation,
    activator: RemappingSource,
    bindings: [RemappingBinding] = [],
    chords: [RemappingChord] = [],
    sequences: [RemappingSequence] = []
  ) {
    self.id = id
    self.name = name
    self.activationMode = activationMode
    self.activator = activator
    self.bindings = bindings
    self.chords = chords
    self.sequences = sequences
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case activationMode = "activation_mode"
    case activator
    case bindings
    case chords
    case sequences
  }
}
