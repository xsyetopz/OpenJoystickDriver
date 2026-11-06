import Foundation

extension RemappingProfile {

  /// Profile document keys of a profile.
  enum CodingKeys: String, CodingKey, CaseIterable {
    /// The JSON key of `apiVersion`.
    case apiVersion
    /// The JSON key of `kind`.
    case kind
    /// The JSON key of `id`.
    case id
    /// The JSON key of `name`.
    case name
    /// The JSON key of `device`.
    case device
    /// The JSON key of `applicationScope`.
    case applicationScope
    /// The JSON key of `outputPolicy`.
    case outputPolicy
    /// The JSON key of `physicalColor`.
    case physicalColor
    /// The JSON key of `motionTuning`.
    case motionTuning
    /// The JSON key of `gyroOutput`.
    case gyroOutput
    /// The JSON key of `joyConPair`.
    case joyConPair
    /// The JSON key of `stickMappings`.
    case stickMappings
    /// The JSON key of `triggerMappings`.
    case triggerMappings
    /// The JSON key of `touchMappings`.
    case touchMappings
    /// The JSON key of `bindings`.
    case bindings
    /// The JSON key of `chords`.
    case chords
    /// The JSON key of `sequences`.
    case sequences
    /// The JSON key of `layers`.
    case layers
  }

  /// Encodes a profile with the current API version and kind; it leaves out motion tuning, gyro
  /// output and the stick, trigger and touch mappings that hold their default.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(OpenJoystickDriverAPI.version, forKey: .apiVersion)
    try container.encode(Self.kind, forKey: .kind)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encode(device, forKey: .device)
    try container.encode(applicationScope, forKey: .applicationScope)
    try container.encode(outputPolicy, forKey: .outputPolicy)
    try container.encodeIfPresent(physicalColor, forKey: .physicalColor)
    if motionTuning != .default { try container.encode(motionTuning, forKey: .motionTuning) }
    if gyroOutput != .default { try container.encode(gyroOutput, forKey: .gyroOutput) }
    try container.encodeIfPresent(joyConPair, forKey: .joyConPair)
    if !stickMappings.isEmpty { try container.encode(stickMappings, forKey: .stickMappings) }
    if !triggerMappings.isEmpty { try container.encode(triggerMappings, forKey: .triggerMappings) }
    if !touchMappings.isEmpty { try container.encode(touchMappings, forKey: .touchMappings) }
    try container.encode(bindings, forKey: .bindings)
    try container.encode(chords, forKey: .chords)
    try container.encode(sequences, forKey: .sequences)
    try container.encode(layers, forKey: .layers)
  }
}
