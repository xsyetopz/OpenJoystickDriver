import Foundation

/// An operating-system permission that an action needs before it acts.
public enum RemappingPermission: String, Codable, CaseIterable, Sendable {
  /// Access to post keyboard, pointer and system key events (Accessibility access).
  case postEvent = "PostEvent"
  /// Access to send an Apple Event to another application.
  case automation = "Automation"
}

/// A system-defined key of `ev_keymap.h` that the `SystemKey` destination sends.
public enum RemappingSystemKey: String, Codable, CaseIterable, Sendable {
  /// Play or pause media.
  case playPause = "PlayPause"
  /// Next track.
  case nextTrack = "NextTrack"
  /// Previous track.
  case previousTrack = "PreviousTrack"
  /// Fast-forward.
  case fastForward = "FastForward"
  /// Rewind.
  case rewind = "Rewind"
  /// Raise the volume.
  case volumeUp = "VolumeUp"
  /// Lower the volume.
  case volumeDown = "VolumeDown"
  /// Mute the sound.
  case mute = "Mute"
  /// Raise the display brightness.
  case brightnessUp = "BrightnessUp"
  /// Lower the display brightness.
  case brightnessDown = "BrightnessDown"
  /// Raise the keyboard illumination.
  case keyboardIlluminationUp = "KeyboardIlluminationUp"
  /// Lower the keyboard illumination.
  case keyboardIlluminationDown = "KeyboardIlluminationDown"
}

/// A system action that did not run.
public enum RemappingSystemActionError: Error, Equatable, LocalizedError, Sendable {
  /// The permission is not granted, so the action sent nothing.
  case permissionMissing(RemappingPermission, action: String)

  /// The catalog code of the failure.
  public var errorCode: ErrorCode {
    switch self {
    case .permissionMissing(.postEvent, _): .postEventAccessMissing
    case .permissionMissing(.automation, _): .automationAccessMissing
    }
  }

  /// The explanation of the code, led by the name of the action.
  public var errorDescription: String? {
    switch self {
    case .permissionMissing(_, let action): "\(action): \(errorCode.localizedExplanation)"
    }
  }
}

/// Performs system actions for the engine; the macOS platform implements it.
///
/// Each method checks its permission first and throws ``RemappingSystemActionError`` without
/// acting when the permission is missing.
public protocol RemappingSystemActionPerforming: Sendable {
  /// Sends one system-defined key event: key down for `pressed`, key up otherwise.
  func postSystemKey(_ key: RemappingSystemKey, pressed: Bool) async throws
  /// Opens Mission Control.
  func openMissionControl() async throws
  /// Opens the application with the bundle identifier.
  func openApplication(bundleIdentifier: String) async throws
  /// Opens the URL.
  func openURL(_ url: URL) async throws
  /// Runs the shortcut with the name.
  func runShortcut(name: String) async throws
  /// Types the text in order, leaving no modifier down.
  func typeText(_ text: String) async throws
}

extension RemappingProfile {
  /// The permissions the profile's actions need, each once.
  ///
  /// Counts destinations in layers, macros and alternate activations, like
  /// ``requiresSystemInputAccess``.
  public var neededPermissions: [RemappingPermission] {
    requiresSystemInputAccess ? [.postEvent] : []
  }
}
