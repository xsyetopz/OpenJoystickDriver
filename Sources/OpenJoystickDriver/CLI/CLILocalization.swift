import Foundation
import OpenJoystickDriverKit

// Headless CLI lookup into the same Kit catalog as the app UI.
enum CLILocalized {
  private static let resolver = Localization()

  static func string(_ key: String, fallback: String) -> String {
    resolver.string(key, defaultValue: fallback)
  }

  static func formatted(_ key: String, fallback: String, _ arguments: CVarArg...) -> String {
    resolver.formatted(key, defaultValue: fallback, arguments: arguments)
  }

  static func text(_ key: String, _ fallback: String) -> String { string(key, fallback: fallback) }

  static func format(_ key: String, _ fallback: String, _ arguments: CVarArg...) -> String {
    formatted(key, fallback: fallback, arguments)
  }
}
