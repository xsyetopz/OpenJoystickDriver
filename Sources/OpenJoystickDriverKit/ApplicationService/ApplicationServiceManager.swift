import Foundation
import ServiceManagement

/// Manages the main application's login-item registration and obsolete agent migration.
public enum ApplicationServiceManager: Sendable {
  public static let label = "com.openjoystickdriver"
  static let obsoleteAgentLabel = "com.openjoystickdriver.service"
  static let legacyDaemonLabel = "com.openjoystickdriver.daemon"
  static let obsoleteAgentPlistName = "\(obsoleteAgentLabel).plist"
  static let legacyDaemonPlistName = "\(legacyDaemonLabel).plist"
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
    appBundleURL
      .appendingPathComponent("Contents", isDirectory: true)
      .appendingPathComponent("MacOS", isDirectory: true)
      .appendingPathComponent("OpenJoystickDriver", isDirectory: false)
  }

  @available(macOS 13.0, *)
  private static var mainAppService: SMAppService { .mainApp }

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
    try removeObsoleteAgentRegistrations()
    guard #available(macOS 13.0, *) else { throw ManagerError.unsupportedOperatingSystem }
    if mainAppService.status == .notRegistered {
      try mainAppService.register()
    }
    print("[ApplicationServiceManager] Main app registered for login")
  }

  public static func uninstall() throws {
    UserDefaults.standard.set(true, forKey: launchAtLoginOptOutDefaultsKey)
    try removeObsoleteAgentRegistrations()
    guard #available(macOS 13.0, *) else { throw ManagerError.unsupportedOperatingSystem }
    if mainAppService.status != .notRegistered {
      try mainAppService.unregister()
    }
    print("[ApplicationServiceManager] Main app removed from login items")
  }

  public static func start() throws { try install() }

  /// Ensures login registration is current. The already-running main app owns runtime restart.
  public static func restart() throws {
    try removeObsoleteAgentRegistrations()
    guard #available(macOS 13.0, *) else { throw ManagerError.unsupportedOperatingSystem }
    if mainAppService.status != .notRegistered {
      try mainAppService.unregister()
    }
    try mainAppService.register()
    print("[ApplicationServiceManager] Main app login registration refreshed")
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

    public init(
      installed: Bool,
      activeCount: Int? = nil,
      state: String? = nil,
      pid: Int? = nil
    ) {
      self.installed = installed
      self.activeCount = activeCount
      self.state = state
      self.pid = pid
    }
  }

  static func obsoleteRuntimesHaveStopped(
    agentIsLoaded: Bool,
    daemonIsLoaded: Bool,
    daemonProcessIsRunning: Bool
  ) -> Bool {
    !agentIsLoaded && !daemonIsLoaded && !daemonProcessIsRunning
  }

  static func removeObsoleteAgentRegistrations() throws {
    if #available(macOS 13.0, *) {
      try? SMAppService.agent(plistName: obsoleteAgentPlistName).unregister()
      try? SMAppService.agent(plistName: legacyDaemonPlistName).unregister()
    }

    let domain = "gui/\(getuid())"
    let agentTarget = "\(domain)/\(obsoleteAgentLabel)"
    let daemonTarget = "\(domain)/\(legacyDaemonLabel)"
    _ = try? launchctl(["bootout", agentTarget])
    _ = try? launchctl(["bootout", daemonTarget])
    terminateLegacyDaemon()

    let launchAgents = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    for plistName in [obsoleteAgentPlistName, legacyDaemonPlistName] {
      let url = launchAgents.appendingPathComponent(plistName)
      if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
      }
    }

    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
      let agentIsLoaded = (try? launchctl(["print", agentTarget])) != nil
      let daemonIsLoaded = (try? launchctl(["print", daemonTarget])) != nil
      if obsoleteRuntimesHaveStopped(
        agentIsLoaded: agentIsLoaded,
        daemonIsLoaded: daemonIsLoaded,
        daemonProcessIsRunning: legacyDaemonProcessIsRunning()
      ) {
        return
      }
      Thread.sleep(forTimeInterval: 0.1)
    }
    throw NSError(
      domain: "OpenJoystickDriver.ApplicationServiceManager",
      code: 3,
      userInfo: [
        NSLocalizedDescriptionKey: "An obsolete OpenJoystickDriver agent did not stop in 5 seconds."
      ]
    )
  }

  private static func terminateLegacyDaemon() {
    _ = try? runProcess(
      executableURL: URL(fileURLWithPath: "/usr/bin/killall"),
      arguments: ["-TERM", "OpenJoystickDriverDaemon"],
      timeoutSeconds: 5
    )
  }

  private static func legacyDaemonProcessIsRunning() -> Bool {
    guard
      let result = try? runProcess(
        executableURL: URL(fileURLWithPath: "/usr/bin/pgrep"),
        arguments: ["-x", "OpenJoystickDriverDaemon"],
        timeoutSeconds: 2
      )
    else {
      return false
    }
    return result.terminationStatus == 0
  }

  private static func launchctl(_ arguments: [String]) throws -> String {
    let result = try runProcess(
      executableURL: URL(fileURLWithPath: "/bin/launchctl"),
      arguments: arguments,
      timeoutSeconds: 5
    )
    guard !result.timedOut, result.terminationStatus == 0 else {
      throw NSError(
        domain: "OpenJoystickDriver.ApplicationServiceManager",
        code: Int(result.terminationStatus),
        userInfo: [NSLocalizedDescriptionKey: result.output]
      )
    }
    return result.output
  }

  private static func runProcess(
    executableURL: URL,
    arguments: [String],
    timeoutSeconds: TimeInterval
  ) throws -> BoundedProcessResult {
    try BoundedProcessRunner.run(
      executableURL: executableURL,
      arguments: arguments,
      timeoutSeconds: timeoutSeconds,
      maximumOutputBytes: 1_048_576
    )
  }
}
