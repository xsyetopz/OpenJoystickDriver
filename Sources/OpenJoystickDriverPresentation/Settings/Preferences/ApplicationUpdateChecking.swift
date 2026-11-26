#if canImport(AppKit) && canImport(SwiftUI)

  import Combine
  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// Checks for a newer release of the app.
  protocol ApplicationUpdateChecking: Sendable {
    /// Returns the result of checking the latest release against `currentVersion`, with prereleases
    /// included when `includePrereleases` is true.
    func check(currentVersion: String, includePrereleases: Bool) async -> UpdateCheckState
  }

  extension UpdateChecker: ApplicationUpdateChecking {}

#endif
