import Foundation

enum ApplicationVersion {
  static var current: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
  }
}
