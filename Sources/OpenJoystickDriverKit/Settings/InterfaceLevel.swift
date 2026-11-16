/// How much of the app's interface shows: the `interfaceLevel` setting.
///
/// See `Resources/Schemas/settings.schema.json`.
public enum InterfaceLevel: String, Codable, CaseIterable, Sendable {
  /// The reduced interface; the built-in default.
  case simple = "Simple"
  /// The full interface.
  case advanced = "Advanced"

  /// The level a setting that no layer states takes.
  public static let `default` = Self.simple
}
