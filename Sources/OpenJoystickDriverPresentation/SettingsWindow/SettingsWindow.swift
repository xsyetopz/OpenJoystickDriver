#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit

  /// The Settings window.
  ///
  /// Its toolbar is the only pane switcher, so the window cannot hide it: the View menu's Show
  /// Toolbar and Hide Toolbar item is disabled while it is the key window.
  final class SettingsWindow: NSWindow {
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
      if menuItem.action == #selector(NSWindow.toggleToolbarShown(_:)) { return false }
      return super.validateMenuItem(menuItem)
    }

    override func toggleToolbarShown(_: Any?) {}
  }

#endif
