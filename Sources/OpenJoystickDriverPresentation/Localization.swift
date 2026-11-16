import Foundation
import OpenJoystickDriverKit

// App UI lookup into Kit Localization. Catalog policy is in LOCALIZATION.md.
/// Looks up the text that the OJD app shows in the Kit localization catalog.
enum OJDLocalized {
  /// The Kit resolver that reads the catalog.
  private static let resolver = Localization()

  /// Returns the catalog text for `key`.
  static func string(_ key: String) -> String { resolver.string(key) }

  /// Returns the catalog text for `key` with `arguments` filled into its placeholders.
  static func formatted(_ key: String, _ arguments: any CVarArg...) -> String {
    resolver.formatted(key, arguments: arguments)
  }

  /// Returns the plural form of `key` that matches `count`.
  static func plural(_ key: String, count: Int) -> String { resolver.plural(key, count: count) }

  /// Returns the plural form of `key` from a `Localizable.stringsdict` entry.
  ///
  /// The entry's count is one of `arguments`, in the entry's order.
  static func plural(_ key: String, _ arguments: any CVarArg...) -> String {
    resolver.plural(key, arguments: arguments)
  }
}
