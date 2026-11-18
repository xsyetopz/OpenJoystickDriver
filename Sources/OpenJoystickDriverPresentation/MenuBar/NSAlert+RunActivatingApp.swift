#if canImport(AppKit)

  import AppKit

  extension NSAlert {
    /// Runs the alert modally after bringing the app forward: the menu bar app has no Dock icon,
    /// so without activation the alert opens behind the windows of the active app.
    @MainActor
    @discardableResult
    func runActivatingApp() -> NSApplication.ModalResponse {
      AppForeground.activate()
      return runModal()
    }
  }

#endif
