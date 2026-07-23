/// Authorization state for posting remapped keyboard and pointer events.
///
/// CoreGraphics only reports whether access is currently granted. A false
/// preflight is therefore `notAuthorized`, not proof that the user denied it.
public enum RemappingPostEventAccessState: String, Codable, Equatable, Sendable {
  case granted
  case notAuthorized = "not_authorized"
}
