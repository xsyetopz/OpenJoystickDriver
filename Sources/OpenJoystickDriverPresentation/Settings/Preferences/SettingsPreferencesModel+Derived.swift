#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit

  extension SettingsPreferencesModel {
    /// Whether the developer tools show: the level is Advanced and the developer tools are on.
    var developerToolsVisible: Bool { interfaceLevel == .advanced && developerToolsEnabled }

    /// Whether Show in Menu Bar cannot be turned off, because the Dock icon is off.
    ///
    /// The two cannot both be off.
    var showInMenuBarIsLocked: Bool { showInMenuBar && !showInDock }

    /// Whether Show in Dock cannot be turned off, because the menu bar item is off.
    ///
    /// The two cannot both be off.
    var showInDockIsLocked: Bool { showInDock && !showInMenuBar }

    /// The text of an outcome that is not `shown`.
    static func message(for outcome: TestNotificationOutcome) -> String? {
      switch outcome {
      case .shown: return nil
      case .denied: return OJDLocalized.string("error.E2037.message")
      case .failed(let reason): return reason
      case .noAnswer: return OJDLocalized.string("error.E2036.message")
      }
    }

    /// Opens the page of the available release in the default browser; does nothing unless a
    /// release is available.
    func openAvailableUpdate() {
      guard case .available(let info) = updateState else { return }
      NSWorkspace.shared.open(info.htmlURL)
    }

    /// The failure that belongs beside the control `origin`, or nil.
    func failure(beside origin: SettingsControlOrigin) -> String? {
      controlFailure?.origin == origin ? controlFailure?.message : nil
    }
  }

#endif
