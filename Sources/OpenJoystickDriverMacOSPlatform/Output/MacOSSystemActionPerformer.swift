import AppKit
import Carbon.HIToolbox
package import Foundation
package import OpenJoystickDriverKit

/// Performs system actions through AppKit, Core Graphics and the `shortcuts` tool.
package struct MacOSSystemActionPerformer: RemappingSystemActionPerforming {
  /// Creates the performer.
  package init() {}

  /// Posts one system-defined key event to the HID event tap.
  package func postSystemKey(_ key: RemappingSystemKey, pressed: Bool) throws {
    try requirePostEvent("SystemKey")
    let state = pressed ? 0xA00 : 0xB00
    guard
      let event = NSEvent.otherEvent(
        with: .systemDefined,
        location: .zero,
        modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state)),
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        subtype: 8,
        data1: (Self.keyType(key) << 16) | state,
        data2: -1
      )?.cgEvent
    else { throw RemappingSystemActionError.failed(action: "SystemKey", reason: key.rawValue) }
    event.post(tap: .cghidEventTap)
  }

  /// Opens the Mission Control application.
  package func openMissionControl() async throws {
    try await open(
      URL(fileURLWithPath: "/System/Applications/Mission Control.app"),
      action: "MissionControl"
    )
  }

  /// Opens Launchpad, or Apps where the system has no Launchpad.
  package func openLaunchpad() async throws {
    for identifier in ["com.apple.launchpad.launcher", "com.apple.apps.launcher"] {
      if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
        try await open(url, action: "Launchpad")
        return
      }
    }
    throw RemappingSystemActionError.failed(
      action: "Launchpad",
      reason: "com.apple.launchpad.launcher"
    )
  }

  /// Takes a screenshot of the screen with the system shortcut Shift-Command-3.
  package func takeScreenshot() throws {
    try postShortcut(CGKeyCode(kVK_ANSI_3), [.maskCommand, .maskShift], action: "Screenshot")
  }

  /// Locks the screen with the system shortcut Control-Command-Q.
  package func lockScreen() throws {
    try postShortcut(CGKeyCode(kVK_ANSI_Q), [.maskCommand, .maskControl], action: "LockScreen")
  }

  /// Shows the desktop with the system shortcut F11.
  package func showDesktop() throws {
    try postShortcut(CGKeyCode(kVK_F11), [], action: "ShowDesktop")
  }

  /// Opens the application with the bundle identifier.
  package func openApplication(bundleIdentifier: String) async throws {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    else {
      throw RemappingSystemActionError.failed(
        action: "OpenApplication",
        reason: bundleIdentifier
      )
    }
    try await open(url, action: "OpenApplication")
  }

  /// Opens the URL in its default handler.
  package func openURL(_ url: URL) throws {
    guard NSWorkspace.shared.open(url) else {
      throw RemappingSystemActionError.failed(action: "OpenURL", reason: url.absoluteString)
    }
  }

  /// Runs the shortcut and waits for it to finish.
  package func runShortcut(name: String) async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
    process.arguments = ["run", name]
    let errors = Pipe()
    process.standardError = errors
    let status: Int32 = try await withCheckedThrowingContinuation { continuation in
      process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
      do { try process.run() } catch { continuation.resume(throwing: error) }
    }
    guard status == 0 else {
      let output = String(bytes: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
      throw RemappingSystemActionError.failed(
        action: "RunShortcut",
        reason: output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? name
      )
    }
  }

  /// Types the text one character at a time as keyboard events.
  package func typeText(_ text: String) throws {
    try requirePostEvent("TypeText")
    guard !IsSecureEventInputEnabled() else { throw RemappingSystemActionError.secureInputEnabled }
    for character in text {
      let units = Array(String(character).utf16)
      for isDown in [true, false] {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: isDown) else {
          throw RemappingSystemActionError.failed(action: "TypeText", reason: String(character))
        }
        unsafe event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        event.post(tap: .cghidEventTap)
      }
    }
  }

  /// Presses and releases the key with the modifiers held.
  private func postShortcut(_ key: CGKeyCode, _ flags: CGEventFlags, action: String) throws {
    try requirePostEvent(action)
    for isDown in [true, false] {
      guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: isDown) else {
        throw RemappingSystemActionError.failed(action: action, reason: String(key))
      }
      event.flags = flags
      event.post(tap: .cghidEventTap)
    }
  }

  /// Opens the application at the URL.
  private func open(_ url: URL, action: String) async throws {
    do {
      _ = try await NSWorkspace.shared.openApplication(
        at: url,
        configuration: NSWorkspace.OpenConfiguration()
      )
    } catch {
      throw RemappingSystemActionError.failed(
        action: action,
        reason: error.localizedDescription
      )
    }
  }

  /// Refuses to post events when the process has no Post Event access.
  private func requirePostEvent(_ action: String) throws {
    guard CGPreflightPostEventAccess() else {
      throw RemappingSystemActionError.permissionMissing(.postEvent, action: action)
    }
  }

  /// The `NX_KEYTYPE` code of the key.
  private static func keyType(_ key: RemappingSystemKey) -> Int {
    switch key {
    case .volumeUp: 0
    case .volumeDown: 1
    case .brightnessUp: 2
    case .brightnessDown: 3
    case .mute: 7
    case .playPause: 16
    case .nextTrack: 17
    case .previousTrack: 18
    case .fastForward: 19
    case .rewind: 20
    case .keyboardIlluminationUp: 21
    case .keyboardIlluminationDown: 22
    }
  }
}
