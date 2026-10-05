#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  extension ApplicationSettingsView {

    var updateStatusTitle: String {
      switch preferences.updateState {
      case .idle: return OJDLocalized.string("settings.updateIdle")
      case .checking: return OJDLocalized.string("settings.updateChecking")
      case .upToDate: return OJDLocalized.string("settings.upToDate")
      case .available:
        return OJDLocalized.string("settings.updateAvailable")
      case .failed:
        return OJDLocalized.string("settings.updateFailed")
      }
    }

    var updateStatusDetail: String {
      switch preferences.updateState {
      case .idle:
        return OJDLocalized.formatted(
          "settings.currentVersion",
          ApplicationVersion.current
        )
      case .checking:
        return OJDLocalized.string("settings.contactingGitHub")
      case .upToDate(let tag): return tag
      case .available(let info): return info.tagName
      case .failed(let failure): return failure.message
      }
    }
  }

#endif
