import Foundation
import OpenJoystickDriverKit

/// The Updates status row of Settings > General for an update check state: the status as the row's
/// label, a version number as its value, and, only while the running version is newer than the
/// latest release, a line naming that release.
///
/// Versions show without the leading `v` of a release tag.
struct UpdateStatusPresentation: Equatable {
  /// What leads the status label.
  ///
  /// It repeats what the label says, so it is hidden from VoiceOver.
  enum Indicator: Equatable {
    /// No indicator.
    case none
    /// A progress indicator while the check runs.
    case progress
    /// An SF Symbol named `name`, colored by `tone`.
    case symbol(name: String, tone: Tone)
  }

  /// How the color of the status symbol reads.
  enum Tone: Equatable {
    /// The running version is the latest release.
    case positive
    /// A newer release can be installed.
    case attention
    /// The running version is newer than the latest release.
    case informational
    /// The check failed.
    case failure
  }

  /// What leads the status label.
  let indicator: Indicator
  /// The status label.
  let title: String
  /// The version number.
  let version: String
  /// The line that names the latest release, or nil for none.
  let latestRelease: String?

  /// Creates the presentation for an update check state.
  ///
  /// - Parameters:
  ///   - state: the result of the update check.
  ///   - runningVersion: the version of the running app.
  init(state: UpdateCheckState, runningVersion: String) {
    var version = runningVersion
    var latestRelease: String?
    switch state {
    case .idle:
      indicator = .none
      title = OJDLocalized.string("ui.settings.general.version")
    case .checking:
      indicator = .progress
      title = OJDLocalized.string("ui.settings.general.updateChecking")
    case .upToDate(let current, _):
      indicator = .symbol(name: "checkmark.circle.fill", tone: .positive)
      title = OJDLocalized.string("ui.settings.general.upToDate")
      version = current
    case .available(let info):
      indicator = .symbol(name: "arrow.down.circle.fill", tone: .attention)
      title = OJDLocalized.string("ui.settings.general.updateAvailable")
      version = Self.versionText(ofTag: info.tagName)
    case .aheadOfLatestRelease(let current, let latest):
      indicator = .symbol(name: "arrow.up.circle.fill", tone: .informational)
      title = OJDLocalized.string("ui.settings.general.updateAhead")
      version = current
      latestRelease = OJDLocalized.formatted(
        "ui.settings.general.latestRelease",
        Self.versionText(ofTag: latest)
      )
    case .failed(let failure):
      indicator = .symbol(name: "xmark.circle.fill", tone: .failure)
      title = failure.message
    }
    self.version = version
    self.latestRelease = latestRelease
  }

  /// A release tag as a version number: `v1.2.3` shows as `1.2.3`.
  static func versionText(ofTag tag: String) -> String {
    guard tag.first == "v", tag.dropFirst().first?.isNumber == true else { return tag }
    return String(tag.dropFirst())
  }
}
