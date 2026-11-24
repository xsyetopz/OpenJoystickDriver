#if canImport(AppKit)

  import AppKit

  /// Keeps AppKit's game controller navigation session running for the life of the process.
  ///
  /// AppKit runs one navigation session per process. The first focus controller an alert window
  /// registers begins the session, which activates a GameController device session
  /// asynchronously, and releasing the last registered alert window ends it. Ending it before the
  /// activation completes makes GameController raise "A session may not be invalidated prior to
  /// activation" from `-[NSWindow dealloc]`, which aborts the process. Activation takes longer
  /// while gamepads connect and disconnect, as they do around OJD's virtual devices. A probe app
  /// that loaded and released 3000 `NSAlert` windows while a virtual pad reconnected aborted in
  /// 4 of 4 runs, and in 0 of 4 runs with one alert window held. Holding a plain titled window,
  /// shown or not, still aborted in 4 of 4 runs: its focus controller doesn't keep the session.
  /// No Info.plist key or user default turns the navigation off:
  /// `NSSupportsGameControllerNavigation`, `NSSupportsFocusNavigation` and
  /// `GCSupportsControllerUserInteraction` each still aborted in 4 of 4 runs.
  ///
  /// One alert window, loaded before any other window and never released, keeps the session
  /// registered, so no later alert can end it during activation.
  @MainActor
  enum ControllerNavigationSession {
    /// The alert whose window keeps the session registered.
    private(set) static var holder: NSAlert?

    /// Loads the held alert's window, once.
    static func hold() {
      guard holder == nil else { return }
      let alert = NSAlert()
      _ = alert.window
      holder = alert
    }
  }

#endif
