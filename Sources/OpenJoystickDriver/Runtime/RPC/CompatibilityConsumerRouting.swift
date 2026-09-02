import AppKit
import OpenJoystickDriverKit

enum CompatibilityConsumerRouting {
  static func changes() -> AsyncStream<CompatibilityConsumerFamily> {
    AsyncStream { continuation in
      final class TokenBox: @unchecked Sendable { var token: NSObjectProtocol? }
      let box = TokenBox()
      box.token = observe { continuation.yield(current()) }
      continuation.onTermination = { _ in
        if let token = box.token { NSWorkspace.shared.notificationCenter.removeObserver(token) }
      }
    }
  }

  static func observe(_ change: @escaping @Sendable () -> Void) -> NSObjectProtocol {
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { _ in change() }
  }

  static func current() -> CompatibilityConsumerFamily {
    guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
      return .unknown
    }
    switch bundleID {
    case "com.google.Chrome", "com.brave.Browser": return .chromiumGamepad
    case "com.apple.Safari": return .webkitGamepad
    case "org.mozilla.firefox": return .geckoGamepad
    case "com.valvesoftware.Steam", "net.pcsx2.pcsx2": return .sdlHIDAPI
    default: return .unknown
    }
  }
}
