import OpenJoystickDriverKit

func duplicatedProfile(_ source: RemappingProfile) -> RemappingProfile {
  RemappingProfile(
    name: OJDLocalized.formatted("profiles.copyName", fallback: "%@ Copy", source.name),
    device: source.device,
    applicationScope: source.applicationScope,
    outputPolicy: source.outputPolicy,
    motionTuning: source.motionTuning,
    gyroOutput: source.gyroOutput,
    joyConPair: source.joyConPair,
    stickMappings: source.stickMappings,
    triggerMappings: source.triggerMappings,
    touchMappings: source.touchMappings,
    bindings: source.bindings,
    chords: source.chords,
    sequences: source.sequences,
    layers: source.layers
  )
}
