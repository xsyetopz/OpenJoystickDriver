import AppKit
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
@MainActor
struct SettingsWindowTests {
  private static func item(_ action: Selector) -> NSMenuItem {
    NSMenuItem(title: "", action: action, keyEquivalent: "")
  }

  @Test
  func settingsWindowDisablesShowAndHideToolbar() {
    let window = SettingsWindow(
      contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: true
    )
    window.toolbar = NSToolbar(identifier: "test")
    #expect(!window.validateMenuItem(Self.item(#selector(NSWindow.toggleToolbarShown(_:)))))
    window.toggleToolbarShown(nil)
    #expect(window.toolbar?.isVisible == true)
    #expect(window.validateMenuItem(Self.item(#selector(NSWindow.performClose(_:)))))
  }
}
