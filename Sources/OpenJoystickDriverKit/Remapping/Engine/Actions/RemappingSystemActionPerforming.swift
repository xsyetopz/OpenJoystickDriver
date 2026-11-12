public import Foundation

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

/// A system action without a parameter.
public enum RemappingSystemActionKind: String, Codable, CaseIterable, Sendable {
  /// Opens Mission Control.
  case missionControl = "MissionControl"
  /// Opens Launchpad, or the Apps app that replaces it where Launchpad is gone.
  case launchpad = "Launchpad"
  /// Opens the Screenshot app, which shows the capture toolbar.
  case screenshot = "Screenshot"
}

/// One call to a ``RemappingSystemActionPerforming``, as the engine produces it.
enum RemappingSystemActionRequest: Equatable, Sendable {
  /// A system key down or up.
  case key(RemappingSystemKey, pressed: Bool)
  /// Open Mission Control.
  case missionControl
  /// Open Launchpad.
  case launchpad
  /// Open the Screenshot app.
  case screenshot
  /// Open the application with the bundle identifier.
  case openApplication(String)
  /// Open the URL.
  case openURL(String)
  /// Run the shortcut with the name.
  case runShortcut(String)
  /// Type the text.
  case typeText(String)
}

/// A system action that did not run.
public enum RemappingSystemActionError: Error, Equatable, LocalizedError, Sendable {
  /// The permission is not granted, so the action sent nothing.
  case permissionMissing(RemappingPermission, action: String)
  /// Secure event input is on, so typing would reach no field.
  case secureInputEnabled
  /// The action ran and failed, for the reason given.
  case failed(action: String, reason: String)

  /// The catalog code of the failure.
  public var errorCode: ErrorCode {
    switch self {
    case .permissionMissing(.postEvent, _): .postEventAccessMissing
    case .permissionMissing(.automation, _): .automationAccessMissing
    case .secureInputEnabled: .secureInputEnabled
    case .failed: .systemActionFailed
    }
  }

  /// The explanation of the code, led by the name of the action.
  public var errorDescription: String? {
    switch self {
    case .permissionMissing(_, let action): "\(action): \(errorCode.localizedExplanation)"
    case .secureInputEnabled: errorCode.localizedExplanation
    case .failed(let action, let reason):
      "\(action): \(errorCode.localizedExplanation) \(reason)"
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
  /// Opens Launchpad, or Apps where Launchpad is gone.
  func openLaunchpad() async throws
  /// Opens the Screenshot app.
  func openScreenshot() async throws
  /// Opens the application with the bundle identifier.
  func openApplication(bundleIdentifier: String) async throws
  /// Opens the URL.
  func openURL(_ url: URL) async throws
  /// Runs the shortcut with the name.
  func runShortcut(name: String) async throws
  /// Types the text in order, leaving no modifier down.
  func typeText(_ text: String) async throws
}

extension RemappingSystemActionPerforming {
  /// Performs a request, with a URL that does not parse reported as a failure.
  func perform(_ request: RemappingSystemActionRequest) async throws {
    switch request {
    case .key(let key, let pressed): try await postSystemKey(key, pressed: pressed)
    case .missionControl: try await openMissionControl()
    case .launchpad: try await openLaunchpad()
    case .screenshot: try await openScreenshot()
    case .openApplication(let identifier): try await openApplication(bundleIdentifier: identifier)
    case .openURL(let text):
      guard let url = URL(string: text) else {
        throw RemappingSystemActionError.failed(action: "OpenURL", reason: text)
      }
      try await openURL(url)
    case .runShortcut(let name): try await runShortcut(name: name)
    case .typeText(let text): try await typeText(text)
    }
  }
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
