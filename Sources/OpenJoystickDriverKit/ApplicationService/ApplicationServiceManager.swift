import Foundation
import ServiceManagement

/// Manages the main application's login-item registration.
public enum ApplicationServiceManager: Sendable {
  public static let label = "com.openjoystickdriver"
  static let launchAtLoginOptOutDefaultsKey = "LaunchAtLoginOptOut"

  public enum ManagerError: LocalizedError, Sendable {
    case unsupportedOperatingSystem

    public var errorDescription: String? {
      switch self {
      case .unsupportedOperatingSystem:
        return "Launching the main app at login requires macOS 13 or later."
      }
    }
  }

  public static func applicationExecutableURL(in appBundleURL: URL) -> URL {
    appBundleURL.appendingPathComponent("Contents", isDirectory: true).appendingPathComponent(
      "MacOS",
      isDirectory: true
    ).appendingPathComponent("OpenJoystickDriver", isDirectory: false)
  }

  @available(macOS 13.0, *) private static var mainAppService: SMAppService { .mainApp }

  public static var isInstalled: Bool {
    guard #available(macOS 13.0, *) else { return false }
    return mainAppService.status != .notRegistered
  }

  /// Registers the main application itself to launch on subsequent logins.
  public static func install() throws {
    UserDefaults.standard.set(false, forKey: launchAtLoginOptOutDefaultsKey)
    try registerMainApp()
  }

  /// Registers on first launch unless the user explicitly removed the login item.
  public static func installByDefaultIfNeeded() throws {
    guard !UserDefaults.standard.bool(forKey: launchAtLoginOptOutDefaultsKey) else { return }
    try registerMainApp()
  }

  private static func registerMainApp() throws {
    guard #available(macOS 13.0, *) else { throw ManagerError.unsupportedOperatingSystem }
    if mainAppService.status == .notRegistered { try mainAppService.register() }
    log("[ApplicationServiceManager] Main app registered for login")
  }

  public static func uninstall() throws {
    UserDefaults.standard.set(true, forKey: launchAtLoginOptOutDefaultsKey)
    guard #available(macOS 13.0, *) else { throw ManagerError.unsupportedOperatingSystem }
    if mainAppService.status != .notRegistered { try mainAppService.unregister() }
    log("[ApplicationServiceManager] Main app removed from login items")
  }

  public static func health() -> ApplicationServiceHealth {
    let processIdentifier = LocalServiceRPCClient.serverProcessIdentifier()
    return ApplicationServiceHealth(
      installed: isInstalled,
      activeCount: processIdentifier == nil ? 0 : 1,
      state: processIdentifier == nil ? "not running" : "running",
      pid: processIdentifier.map(Int.init)
    )
  }

  public struct ApplicationServiceHealth: Sendable {
    public var installed: Bool
    public var activeCount: Int?
    public var state: String?
    public var pid: Int?

    public init(installed: Bool, activeCount: Int? = nil, state: String? = nil, pid: Int? = nil) {
      self.installed = installed
      self.activeCount = activeCount
      self.state = state
      self.pid = pid
    }
  }

  private static func log(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
  }
}
