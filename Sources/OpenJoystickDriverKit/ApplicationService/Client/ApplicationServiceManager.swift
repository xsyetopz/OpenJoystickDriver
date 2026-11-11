public import Foundation

/// The state of the main app's login-item registration in macOS.
package enum ApplicationServiceRegistrationStatus: Sendable, Equatable {
  /// The app has no login-item registration.
  case notRegistered
  /// The login item is registered, and macOS opens the app at login.
  case enabled
  /// The login item is registered, and the user must approve it in System Settings.
  case requiresApproval
  /// macOS cannot find the login item.
  case notFound
}

/// The login-item registration of the main app, which the platform host provides.
package protocol ApplicationServiceRegistration: Sendable {
  /// The registration state that macOS reports.
  var status: ApplicationServiceRegistrationStatus { get }

  /// Registers the main app as a login item.
  func register() throws
  /// Removes the main app's login item.
  func unregister() throws
}

/// Manages the main application's login-item registration.
public enum ApplicationServiceManager: Sendable {
  /// The label of the main app's login-item registration.
  public static let label = "com.openjoystickdriver"

  /// The failures of registering the main app as a login item.
  public enum ManagerError: LocalizedError, Sendable {
    /// The running macOS is older than 13, which has no login-item registration.
    case unsupportedOperatingSystem

    /// The description of the error for the user.
    public var errorDescription: String? {
      switch self {
      case .unsupportedOperatingSystem:
        return "Launching the main app at login requires macOS 13 or later."
      }
    }
  }

  /// The path of the main app's executable inside the bundle at `appBundleURL`.
  public static func applicationExecutableURL(in appBundleURL: URL) -> URL {
    appBundleURL.appendingPathComponent("Contents", isDirectory: true).appendingPathComponent(
      "MacOS",
      isDirectory: true
    ).appendingPathComponent("OpenJoystickDriver", isDirectory: false)
  }

  /// Whether the main app has a login-item registration in any state; false before macOS 13.
  public static var isInstalled: Bool {
    guard #available(macOS 13.0, *) else { return false }
    return PlatformHosts.current.mainAppRegistration.status != .notRegistered
  }

  /// Whether macOS will open the main application at login; false while approval is pending.
  public static var isLaunchAtLoginEnabled: Bool {
    guard #available(macOS 13.0, *) else { return false }
    return PlatformHosts.current.mainAppRegistration.status == .enabled
  }

  /// Registers the main application itself to launch on subsequent logins.
  ///
  /// Records the choice in `settings` first; a settings file that cannot be read or written stops
  /// the call before it registers.
  public static func install(settings: SettingsStore = SettingsStore()) throws {
    try settings.set(.launchAtLogin, to: true)
    try registerMainApp()
  }

  /// Registers on first launch unless the user explicitly removed the login item.
  public static func installByDefaultIfNeeded(settings: SettingsStore = SettingsStore()) throws {
    guard !(try settings.launchAtLoginOptOut()) else { return }
    try registerMainApp()
  }

  /// Registers the main app through the current platform host.
  private static func registerMainApp() throws {
    try registerMainApp(using: PlatformHosts.current.mainAppRegistration)
  }

  /// Registers the main app through `service` unless it is registered, and writes a line to
  /// `information`.
  ///
  /// - Throws: ``ManagerError/unsupportedOperatingSystem`` before macOS 13, and the error of
  ///   `service` when registration fails.
  static func registerMainApp(
    using service: any ApplicationServiceRegistration,
    information: FileHandle = .standardOutput
  ) throws {
    guard #available(macOS 13.0, *) else { throw ManagerError.unsupportedOperatingSystem }
    if service.status == .notRegistered { try service.register() }
    log("[ApplicationServiceManager] Main app registered for login", to: information)
  }

  /// Removes the main app's login item and records in `settings` that launch at login is off.
  ///
  /// - Throws: ``ManagerError/unsupportedOperatingSystem`` before macOS 13, and the error of the
  ///   settings store or of the unregistration.
  public static func uninstall(settings: SettingsStore = SettingsStore()) throws {
    try settings.set(.launchAtLogin, to: false)
    try unregisterMainApp(using: PlatformHosts.current.mainAppRegistration)
  }

  /// Unregisters the main app through `service` when it is registered, and writes a line to
  /// `information`.
  ///
  /// - Throws: ``ManagerError/unsupportedOperatingSystem`` before macOS 13, and the error of
  ///   `service` when unregistration fails.
  static func unregisterMainApp(
    using service: any ApplicationServiceRegistration,
    information: FileHandle = .standardOutput
  ) throws {
    guard #available(macOS 13.0, *) else { throw ManagerError.unsupportedOperatingSystem }
    if service.status != .notRegistered { try service.unregister() }
    log("[ApplicationServiceManager] Main app removed from login items", to: information)
  }

  /// Reports whether the login item is registered and whether the main app's local server answers.
  public static func health() -> ApplicationServiceHealth {
    let processIdentifier = LocalServiceRPCClient.serverProcessIdentifier()
    return ApplicationServiceHealth(
      installed: isInstalled,
      activeCount: processIdentifier == nil ? 0 : 1,
      state: processIdentifier == nil ? "not running" : "running",
      pid: processIdentifier.map(Int.init)
    )
  }

  /// The login-item registration and the running state of the main app.
  public struct ApplicationServiceHealth: Sendable {
    /// Whether the main app has a login-item registration.
    public var installed: Bool
    /// 1 when the main app's local server answers, otherwise 0.
    public var activeCount: Int?
    /// `running` when the main app's local server answers, otherwise `not running`.
    public var state: String?
    /// The process identifier of the main app's local server; nil when none answers.
    public var pid: Int?

    /// Creates a health report from its values.
    public init(installed: Bool, activeCount: Int? = nil, state: String? = nil, pid: Int? = nil) {
      self.installed = installed
      self.activeCount = activeCount
      self.state = state
      self.pid = pid
    }
  }

  /// Writes an informational line to standard output, which the Activity console lists as output;
  /// standard error is reserved for errors.
  private static func log(_ message: String, to information: FileHandle) {
    information.write(Data((message + "\n").utf8))
  }
}
