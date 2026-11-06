import Foundation

extension RemappingProfile {
  /// Whether the profile maps anything to output.
  public var hasOutputMappings: Bool {
    if gyroOutput.mode != .disabled || !stickMappings.isEmpty || !touchMappings.isEmpty
      || motionTuning.steering != nil
      || layers.contains(where: { $0.motionTuning?.steering != nil })
    {
      return true
    }
    if !bindings.isEmpty || !chords.isEmpty || !sequences.isEmpty { return true }
    return layers.contains { layer in
      !layer.bindings.isEmpty || !layer.chords.isEmpty || !layer.sequences.isEmpty
    }
  }
}

extension ApplicationServiceRemappingSnapshotPayload {
  /// Whether an active profile posts keyboard, pointer or scroll events, so Post Event access is
  /// needed.
  ///
  /// An active profile without its record is an incomplete snapshot and counts as requiring it, so
  /// the answer never claims output is safe to dispatch.
  public var requiresPostEventAccess: Bool {
    activeProfiles.contains { activeProfile in
      guard let profile = profiles.first(where: { $0.id == activeProfile.profileID }) else {
        return true
      }
      return profile.hasOutputMappings && profile.requiresSystemInputAccess
    }
  }
}
