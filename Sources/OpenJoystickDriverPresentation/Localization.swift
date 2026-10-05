import Foundation
import OpenJoystickDriverKit

// App UI lookup into Kit Localization. Catalog policy is in LOCALIZATION.md.
enum OJDLocalized {
  private static let resolver = Localization()

  static func string(_ key: String) -> String { resolver.string(key) }

  static func formatted(_ key: String, _ arguments: CVarArg...) -> String {
    resolver.formatted(key, arguments: arguments)
  }

  static func plural(_ key: String, count: Int) -> String { resolver.plural(key, count: count) }
}
