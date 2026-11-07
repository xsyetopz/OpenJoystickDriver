#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit

  /// What the app does at launch about a settings file that cannot be used.
  ///
  /// While the settings file can't be read, the menu bar item shows, whatever Show in menu bar
  /// would say, and an alert offers Reset Settings, Show in Finder, and Quit.
  enum SettingsFileStartup: Equatable {
    /// Continue the launch.
    case proceed
    /// Offer to reset the file, show it in Finder or quit.
    case offerRecovery(SettingsStoreError)

    /// Returns ``offerRecovery(_:)`` for a settings error, else ``proceed``.
    static func decide(settingsError: SettingsStoreError?) -> Self {
      settingsError.map(Self.offerRecovery) ?? .proceed
    }

    /// The menu bar item is the one entry point the app is sure to have, so it shows while the
    /// settings file can't be read and the Show in menu bar value is only the default.
    static func statusItemIsShown(showInMenuBar: Bool, settingsError: SettingsStoreError?) -> Bool {
      showInMenuBar || settingsError != nil
    }
  }

  /// The work that waits for a usable settings file, run again when a reset or a repair makes the
  /// file usable: the update check, if enabled, and the login registration, unless the user opted
  /// out.
  @MainActor
  struct SettingsRecoveryFollowUp {
    /// The launch update check.
    let updateCheck: LaunchUpdateCheck
    /// Registers the login item.
    let registerLogin: () throws -> Void

    /// Runs the update check and the login registration.
    ///
    /// A failed registration goes to standard error.
    func run() {
      updateCheck.run()
      do { try registerLogin() } catch {
        FileHandle.standardError.write(
          Data("[Settings] Login registration unavailable: \(error.localizedDescription)\n".utf8)
        )
      }
    }
  }

  /// The button the user pressed in the alert for an unreadable settings file.
  enum SettingsUnreadableChoice: Equatable {
    /// Convert the stale documents.
    case migrate
    /// Show the settings file in Finder.
    case showInFinder
    /// Reset the settings.
    case resetSettings
    /// Quit the app.
    case quit

    /// Maps the alert's button response: Show in Finder and Reset Settings are the first two
    /// buttons, any other response is Quit. An alert that `offersMigration` has Migrate first and
    /// the others after it.
    init(response: NSApplication.ModalResponse, offersMigration: Bool = false) {
      let buttons: [Self] = (offersMigration ? [.migrate] : []) + [.showInFinder, .resetSettings]
      let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
      self = buttons.indices.contains(index) ? buttons[index] : .quit
    }
  }

  /// The alert for a settings file that cannot be read.
  enum SettingsUnreadableAlert {
    /// Returns the alert for `reason`.
    ///
    /// Show in Finder is the default button, or Migrate when the alert `offersMigration`; Reset
    /// Settings is a normal button marked destructive, and Quit answers Escape.
    @MainActor
    static func make(reason: String, offersMigration: Bool = false) -> NSAlert {
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = OJDLocalized.string("ui.settings.advanced.unreadableTitle")
      alert.informativeText = reason
      if offersMigration { alert.addButton(withTitle: OJDLocalized.string("ui.migrate.action")) }
      alert.addButton(
        withTitle: OJDLocalized.string("platform.macos.ui.settings.advanced.unreadableShowInFinder")
      )
      let reset = alert.addButton(
        withTitle: OJDLocalized.string("ui.settings.advanced.unreadableResetSettings")
      )
      reset.hasDestructiveAction = true
      let quit = alert.addButton(
        withTitle: MainMenuRenderer.title(
          "ui.menu.app.quit",
          appName: OJDLocalized.string("term.app.name")
        )
      )
      quit.keyEquivalent = "\u{1b}"
      return alert
    }
  }

  /// The log line for a feature that does nothing while the settings file can't be read.
  enum SettingsSkipLog {
    /// Returns the standard error line that names the skipped feature, the file and the error.
    static func message(feature: String, file: String, error: any Error) -> String {
      "[Settings] \(file) cannot be read, skipping \(feature): \(error.localizedDescription)\n"
    }

    /// Writes the line of ``message(feature:file:error:)`` to standard error.
    static func write(feature: String, file: String, error: any Error) {
      FileHandle.standardError.write(
        Data(message(feature: feature, file: file, error: error).utf8)
      )
    }
  }

#endif
