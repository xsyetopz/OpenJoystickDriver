import Foundation
import OpenJoystickDriverKit

// Headless CLI lookup into the same Kit catalog as the app UI.
/// Looks up `ojd` text in the catalog that the app UI uses.
enum CLILocalized {
  /// The catalog resolver for the preferred languages of the process.
  private static let resolver = Localization()

  /// The text for `key`.
  static func text(_ key: String) -> String { resolver.string(key) }

  /// The text for `key` with `arguments` filled in.
  static func format(_ key: String, _ arguments: CVarArg...) -> String {
    resolver.formatted(key, arguments: arguments)
  }

  /// A `Localizable.stringsdict` plural whose count is one of `arguments`, in the entry's order.
  static func plural(_ key: String, _ arguments: CVarArg...) -> String {
    resolver.plural(key, arguments: arguments)
  }
}
