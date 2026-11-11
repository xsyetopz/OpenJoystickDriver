import OpenJoystickDriverKit

/// Decides at app launch whether the update check runs: only when the settings file can be read and
/// the user enabled "Check for updates automatically".
///
/// An unreadable settings file never runs the check on the default.
@MainActor
struct LaunchUpdateCheck {
  /// The result of the launch decision.
  enum Outcome: Equatable {
    /// The update check ran.
    case checked
    /// The user turned the automatic update check off.
    case disabled
    /// The settings file could not be read, so the check did not run.
    case skippedSettingsUnreadable(SettingsStoreError)
  }

  /// Returns the error that makes the settings file unreadable, or nil when it can be read.
  let settingsError: @MainActor () -> SettingsStoreError?
  /// Returns whether "Check for updates automatically" is on.
  let isEnabled: @MainActor () -> Bool
  /// Starts the update check.
  let check: @MainActor () -> Void

  /// Runs the check when the settings allow it and returns what happened.
  @discardableResult
  func run() -> Outcome {
    if let error = settingsError() { return .skippedSettingsUnreadable(error) }
    guard isEnabled() else { return .disabled }
    check()
    return .checked
  }
}
