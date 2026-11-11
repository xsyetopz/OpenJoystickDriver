/// Authorization state for posting remapped keyboard and pointer events.
///
/// CoreGraphics only reports whether access is currently granted. A false
/// preflight is therefore `notAuthorized`, not proof that the user denied it.
public enum RemappingPostEventAccessState: String, Codable, Equatable, Sendable {
  /// CoreGraphics reports that OJD may post events.
  case granted
  /// CoreGraphics does not report that OJD may post events; the user may have denied it or not
  /// decided.
  case notAuthorized = "not_authorized"
}
