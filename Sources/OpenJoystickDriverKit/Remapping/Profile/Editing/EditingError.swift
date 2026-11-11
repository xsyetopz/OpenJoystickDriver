package import Foundation

/// A profile edit referenced an item that the profile does not contain.
///
/// Editors map these cases to their own user-visible messages.
package enum RemappingProfileEditingError: Error, Equatable, Sendable {
  /// No chord has this identifier.
  case chordNotFound(UUID)
  /// No layer has this identifier.
  case layerNotFound(UUID)
  /// No sequence has this identifier.
  case sequenceNotFound(UUID)
}
