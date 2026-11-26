#if canImport(AppKit) && canImport(SwiftUI)

  import Combine
  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The control of General or Notifications whose failure shows beside it.
  enum SettingsControlOrigin: Equatable {
    /// The Open at login switch.
    case loginItem
    /// The pause shortcut row.
    case pauseShortcut
    /// The Send Test Notification button.
    case testNotification
  }

  /// The failure of a request that a control started, with that control.
  struct SettingsControlFailure: Equatable {
    /// Why the request failed.
    let message: String
    /// The control that started the request.
    let origin: SettingsControlOrigin
  }

#endif
