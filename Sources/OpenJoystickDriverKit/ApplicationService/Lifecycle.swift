import Foundation
import ServiceManagement

enum ApplicationServiceRegistrationStatus: Sendable, Equatable {
  case notRegistered
  case enabled
  case requiresApproval
  case notFound
}

protocol ApplicationServiceRegistration: Sendable {
  var status: ApplicationServiceRegistrationStatus { get }

  func register() throws
  func unregister() throws
}

private struct MainAppServiceRegistration: ApplicationServiceRegistration {
  var status: ApplicationServiceRegistrationStatus {
    guard #available(macOS 13.0, *) else { return .notFound }
    switch SMAppService.mainApp.status {
    case .notRegistered: return .notRegistered
    case .enabled: return .enabled
    case .requiresApproval: return .requiresApproval
    case .notFound: return .notFound
    @unknown default: return .notFound
    }
  }

  func register() throws {
    guard #available(macOS 13.0, *) else {
      throw ApplicationServiceManager.ManagerError.unsupportedOperatingSystem
    }
    try SMAppService.mainApp.register()
  }

  func unregister() throws {
    guard #available(macOS 13.0, *) else {
      throw ApplicationServiceManager.ManagerError.unsupportedOperatingSystem
    }
    try SMAppService.mainApp.unregister()
  }
}

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

  public static var isInstalled: Bool {
    guard #available(macOS 13.0, *) else { return false }
    return MainAppServiceRegistration().status != .notRegistered
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
    try registerMainApp(using: MainAppServiceRegistration())
  }

  static func registerMainApp(using service: any ApplicationServiceRegistration) throws {
    guard #available(macOS 13.0, *) else { throw ManagerError.unsupportedOperatingSystem }
    if service.status == .notRegistered { try service.register() }
    log("[ApplicationServiceManager] Main app registered for login")
  }

  public static func uninstall() throws {
    UserDefaults.standard.set(true, forKey: launchAtLoginOptOutDefaultsKey)
    try unregisterMainApp(using: MainAppServiceRegistration())
  }

  private static func unregisterMainApp(using service: any ApplicationServiceRegistration) throws {
    guard #available(macOS 13.0, *) else { throw ManagerError.unsupportedOperatingSystem }
    if service.status != .notRegistered { try service.unregister() }
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
