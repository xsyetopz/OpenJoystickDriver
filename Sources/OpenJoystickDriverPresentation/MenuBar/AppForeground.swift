#if canImport(AppKit)

  import AppKit

  /// Brings the app and its windows forward, unless `OJD_HIDDEN` is `1`, `true` or `yes`.
  ///
  /// With `OJD_HIDDEN` set, a window is ordered behind the windows of every other app and the app
  /// never activates, so a script can drive the app and capture its windows with
  /// `screencapture -l` while the user keeps working in another app.
  @MainActor
  enum AppForeground {
    /// Whether `OJD_HIDDEN` keeps the app in the background.
    static let isHidden = ["1", "true", "yes"].contains(
      (ProcessInfo.processInfo.environment["OJD_HIDDEN"] ?? "").lowercased()
    )

    /// Activates the app, regardless of the active app.
    static func activate() {
      guard !isHidden else { return }
      NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// Shows the window in front and activates the app, or orders it to the back when hidden.
    ///
    /// - Parameter window: The window to show.
    static func show(_ window: NSWindow) {
      guard !isHidden else {
        window.orderBack(nil)
        return
      }
      window.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
    }
  }

#endif
