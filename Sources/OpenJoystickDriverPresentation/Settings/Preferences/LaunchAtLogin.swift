#if canImport(AppKit)

  import Foundation
  import OpenJoystickDriverKit

  /// Reads and changes the login item that starts the app at login.
  protocol LaunchAtLoginControlling {
    /// Whether this macOS version supports the login item.
    var isAvailable: Bool { get }
    /// Whether the login item is on.
    var isEnabled: Bool { get }
    /// Turns the login item on or off.
    ///
    /// - Throws: the error of ``ApplicationServiceManager`` when the login item cannot be changed.
    func setEnabled(_ enabled: Bool) throws
  }

  /// The macOS login item; the choice is recorded in the settings files, as `ojd setting` does.
  struct SystemLaunchAtLoginController: LaunchAtLoginControlling {
    /// The settings store that records the choice.
    let settings: SettingsStore

    /// Creates the controller on a settings store.
    init(settings: SettingsStore = SettingsStore()) { self.settings = settings }

    /// Whether the login item is supported, which is the case from macOS 13.
    var isAvailable: Bool {
      if #available(macOS 13.0, *) { return true }
      return false
    }

    /// Whether the login item is registered.
    var isEnabled: Bool { ApplicationServiceManager.isLaunchAtLoginEnabled }

    /// Registers or removes the login item.
    ///
    /// - Parameter enabled: Whether the app starts at login.
    /// - Throws: The error of the registration or removal.
    func setEnabled(_ enabled: Bool) throws {
      if enabled {
        try ApplicationServiceManager.install(settings: settings)
      } else {
        try ApplicationServiceManager.uninstall(settings: settings)
      }
    }
  }

#endif
