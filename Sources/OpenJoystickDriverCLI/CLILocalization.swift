import Foundation
import OpenJoystickDriverKit

// Headless CLI lookup into the same Kit catalog as the app UI.
enum CLILocalized {
  private static let resolver = Localization()

  static func text(_ key: String) -> String { resolver.string(key) }

  static func format(_ key: String, _ arguments: CVarArg...) -> String {
    resolver.formatted(key, arguments: arguments)
  }
}
