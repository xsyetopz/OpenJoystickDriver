import Foundation

extension RemappingProfile {

  /// Profile document keys of a profile.
  enum CodingKeys: String, CodingKey, CaseIterable {
    case apiVersion
    case kind
    case id
    case name
    case device
    case applicationScope
    case outputPolicy
    case physicalColor
    case motionTuning
    case gyroOutput
    case joyConPair
    case pointerSpeed
    case stickMappings
    case triggerMappings
    case touchMappings
    case bindings
    case chords
    case sequences
    case layers
    case macros
  }

  /// Encodes a profile with the current API version and kind; it leaves out motion tuning, gyro
  /// output, the stick, trigger and touch mappings that hold their default, and an empty macro
  /// list.
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
    try container.encodeIfPresent(pointerSpeed, forKey: .pointerSpeed)
    if !stickMappings.isEmpty { try container.encode(stickMappings, forKey: .stickMappings) }
    if !triggerMappings.isEmpty { try container.encode(triggerMappings, forKey: .triggerMappings) }
    if !touchMappings.isEmpty { try container.encode(touchMappings, forKey: .touchMappings) }
    try container.encode(bindings, forKey: .bindings)
    try container.encode(chords, forKey: .chords)
    try container.encode(sequences, forKey: .sequences)
    try container.encode(layers, forKey: .layers)
    if !macros.isEmpty { try container.encode(macros, forKey: .macros) }
  }
}
