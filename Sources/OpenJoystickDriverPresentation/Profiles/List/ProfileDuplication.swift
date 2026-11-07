import Foundation
import OpenJoystickDriverKit

/// Trims the name a person typed for a profile.
enum ProfileNameValidation {
  /// Returns `name` without the whitespace and newlines around it.
  static func trimmedName(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

/// Returns the name that the Duplicate sheet starts with: the source's name followed by the copy
/// marker, made free of the names `profiles` already have.
///
/// - Parameters:
///   - source: The profile being duplicated.
///   - profiles: The existing profiles, whose names the copy must not take.
/// - Returns: The name that the Duplicate sheet starts with: the source's name followed by the copy
///   marker, made free of the names `profiles` already have.
func defaultDuplicateName(of source: RemappingProfile, in profiles: [RemappingProfile]) -> String {
  ProfileNaming.availableName(
    OJDLocalized.formatted("ui.profiles.copyName", source.name),
    in: profiles
  )
}

/// Returns a copy of `source` under `name`, or nil when the name is taken among `profiles` or
/// the copy is not a valid profile.
///
/// - Parameters:
///   - source: The profile being duplicated.
///   - name: The name of the copy.
///   - profiles: The existing profiles, whose names the copy must not take.
/// - Returns: A copy of `source` under `name`, or nil when the name is taken among `profiles` or
///   the copy is not a valid profile.
func duplicatedProfile(
  _ source: RemappingProfile,
  named name: String,
  in profiles: [RemappingProfile]
) -> RemappingProfile? {
  guard !ProfileNaming.isTaken(name, in: profiles) else { return nil }
  let copy = RemappingProfile(
    name: ProfileNameValidation.trimmedName(name),
    device: source.device,
    applicationScope: source.applicationScope,
    outputPolicy: source.outputPolicy,
    physicalColor: source.physicalColor,
    motionTuning: source.motionTuning,
    gyroOutput: source.gyroOutput,
    joyConPair: source.joyConPair,
    stickMappings: source.stickMappings,
    triggerMappings: source.triggerMappings,
    touchMappings: source.touchMappings,
    bindings: source.bindings,
    chords: source.chords,
    sequences: source.sequences,
    layers: source.layers,
    macros: source.macros
  )
  return (try? copy.validate()) == nil ? nil : copy
}
