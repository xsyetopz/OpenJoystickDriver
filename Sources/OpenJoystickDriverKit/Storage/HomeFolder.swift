import Foundation

/// How text for a person shows paths under the user's home folder: as `~`, so output and screens
/// stay short and leave out the account name.
///
/// Machine-readable output keeps absolute paths.
public enum HomeFolder {
  /// `text` with each path under `home` written as `~`.
  ///
  /// A longer folder name that starts with `home` is left alone.
  public static func redacting(_ text: String, home: String) -> String {
    let base = home.hasSuffix("/") ? String(home.dropLast()) : home
    guard !base.isEmpty,
      let expression = try? NSRegularExpression(
        pattern: NSRegularExpression.escapedPattern(for: base) + #"(?=$|[/\s"':,;)\]])"#,
        options: .anchorsMatchLines
      )
    else { return text }
    return expression.stringByReplacingMatches(
      in: text,
      range: NSRange(text.startIndex..., in: text),
      withTemplate: "~"
    )
  }

  /// `text` with each path under the current user's home folder written as `~`.
  public static func redacting(_ text: String) -> String {
    redacting(text, home: MacOSDataDirectory().url(for: .home).path)
  }
}
