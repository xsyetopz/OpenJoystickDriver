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
func defaultDuplicateName(of source: RemappingProfile, in profiles: [RemappingProfile]) -> String {
  ProfileNaming.availableName(
    OJDLocalized.formatted("ui.profiles.copyName", source.name),
    in: profiles
  )
}

/// Returns a copy of `source` under `name`, or nil when the name is taken among `profiles` or
/// the copy is not a valid profile.
func duplicatedProfile(
  _ source: RemappingProfile,
  named name: String,
  in profiles: [RemappingProfile]
) -> RemappingProfile? {
  guard !ProfileNaming.isTaken(name, in: profiles) else { return nil }
  let copy = source.copy(id: UUID(), name: ProfileNameValidation.trimmedName(name))
  return (try? copy.validate()) == nil ? nil : copy
}
