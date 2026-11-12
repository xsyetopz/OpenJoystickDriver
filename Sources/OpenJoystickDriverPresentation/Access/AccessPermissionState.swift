import Foundation

/// What a permission row says about its permission, apart from the words it shows as a value.
enum AccessPermissionState: String, CaseIterable, Equatable, Sendable {
  /// The permission is allowed.
  case granted
  /// The permission is denied, or its answer could not be read.
  case denied
  /// The permission has not been requested yet.
  case notAsked
  /// The permission is being read.
  case checking
  /// The active profiles do not use the permission.
  case notNeeded
  /// Notifications are allowed but their banners or sounds are off.
  case limited

  /// The SF Symbol of the state; each has its own shape (circle, octagon, diamond, clock, minus,
  /// bell), so the states differ without color.
  var symbolName: String {
    switch self {
    case .granted: return "checkmark.circle.fill"
    case .denied: return "xmark.octagon.fill"
    case .notAsked: return "questionmark.diamond.fill"
    case .checking: return "clock.fill"
    case .notNeeded: return "minus.square.fill"
    case .limited: return "bell.slash.fill"
    }
  }

  /// The localization key of the one sentence that says what the state means.
  var messageKey: String {
    switch self {
    case .granted: return "ui.access.permission.granted.message"
    case .denied: return "platform.macos.ui.access.permission.denied.message"
    case .notAsked: return "ui.access.permission.notAsked.message"
    case .checking: return "ui.access.permission.checking.message"
    case .notNeeded: return "ui.access.permission.notNeeded.message"
    case .limited: return "ui.access.permission.limited.message"
    }
  }
}
