import Foundation
import OpenJoystickDriverKit

enum OJDLocalized {
  private static let resolver = Localization()

  static func string(_ key: String, fallback: String? = nil) -> String {
    resolver.string(key, defaultValue: fallback ?? key)
  }

  static func formatted(_ key: String, fallback: String? = nil, _ arguments: CVarArg...) -> String {
    resolver.formatted(key, defaultValue: fallback ?? key, arguments: arguments)
  }

  static func plural(_ key: String, count: Int, fallback: String? = nil) -> String {
    resolver.plural(key, count: count, defaultValue: fallback ?? key)
  }
}
