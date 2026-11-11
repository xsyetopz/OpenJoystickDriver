import Foundation

/// The sections of `CHANGELOG.md`, which the Kit bundle holds.
public enum Changelog {
  /// The text of the bundled `CHANGELOG.md`, or nil when the bundle lacks it.
  public static func bundled() -> String? {
    Bundle.module.url(forResource: "CHANGELOG", withExtension: "md").flatMap {
      try? String(contentsOf: $0, encoding: .utf8)
    }
  }

  /// The text under the header `## [version]` of `changelog`, without the blank lines around it.
  ///
  /// The section ends at the next `## [` header or at the link references after the last section.
  /// Returns nil when no header names `version` exactly, or when the section has no text.
  public static func section(of version: String, in changelog: String) -> String? {
    var lines = changelog.split(separator: "\n", omittingEmptySubsequences: false)
      .drop { !$0.hasPrefix("## [\(version)]") }.dropFirst()
    if let end = lines.firstIndex(where: { $0.hasPrefix("## [") || isLinkReference($0) }) {
      lines = lines[..<end]
    }
    let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
  }

  /// The section to show for `installed` when `lastShown` is another version, or nil when the
  /// section of `installed` was shown already or does not exist.
  public static func toShow(installed: String, lastShown: String?, in changelog: String) -> String?
  {
    lastShown == installed ? nil : section(of: installed, in: changelog)
  }

  private static func isLinkReference(_ line: Substring) -> Bool {
    line.hasPrefix("[") && line.contains("]: ")
  }
}
