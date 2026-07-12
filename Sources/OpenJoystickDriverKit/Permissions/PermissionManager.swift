import Foundation
import IOKit
import IOKit.hid

private let permissionPollNanoseconds: UInt64 = 1_000_000_000

/// Manages Input Monitoring permission state for the daemon.
public actor PermissionManager {
  /// The three possible states for a macOS permission.
  public enum AccessState: String, Codable, Sendable, Equatable, CustomStringConvertible {
    /// The user has allowed access.
    case granted
    /// The user has denied access, or the system rejected the request.
    case denied
    /// The permission has not been checked yet in this session.
    case unknown

    /// Creates a normalized state from an XPC value or permission-probe output.
    ///
    /// Helper probes may emit diagnostic lines before the final state, so the
    /// last whitespace-delimited token is treated as the authoritative value.
    public init(status: String) {
      let token = status.split { $0.isWhitespace }.last
      self = token.flatMap { Self(rawValue: String($0).lowercased()) } ?? .unknown
    }

    /// Stable text used by XPC, logs, and command-line output.
    public var description: String { rawValue }

    /// A short status tag suitable for log output or CLI display.
    public var label: String {
      switch self {
      case .granted: return "[OK]"
      case .denied: return "[DENIED]"
      case .unknown: return "[UNKNOWN]"
      }
    }
  }

  /// Current state of the Input Monitoring permission.
  ///
  /// Updated by ``startPolling()`` and ``requestAccess()``.
  public private(set) var inputMonitoringState: AccessState = .unknown
  private var pollingTask: Task<Void, Never>?

  /// Creates a new PermissionManager.
  public init() {}

  /// Returns current Input Monitoring permission state for the current process.
  ///
  /// This is safe to call from short-lived helper probes that need the daemon
  /// bundle's effective TCC state without spinning up the full actor runtime.
  nonisolated public static func currentAccessState() -> AccessState {
    let result = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
    switch result {
    case kIOHIDAccessTypeGranted: return .granted
    case kIOHIDAccessTypeDenied: return .denied
    default: return .unknown
    }
  }

  /// Returns the bundled daemon helper's effective Input Monitoring state.
  ///
  /// The probe runs the daemon binary in check-only mode so macOS evaluates the
  /// daemon helper's TCC identity rather than the calling app's identity.
  nonisolated public static func daemonAccessState(mainBundleURL: URL) -> AccessState {
    let executableURL = DaemonManager.daemonExecutableURL(forMainBundleURL: mainBundleURL)
    guard FileManager.default.fileExists(atPath: executableURL.path) else { return .unknown }

    let environment = ProcessInfo.processInfo.environment.merging(
      ["OJD_PERMISSION_CHECK_ONLY": "1"]
    ) { _, new in new }
    guard
      let result = try? BoundedProcessRunner.run(
        executableURL: executableURL,
        environment: environment,
        timeoutSeconds: 5,
        maximumOutputBytes: 65_536
      ),
      !result.timedOut,
      result.terminationStatus == 0
    else {
      return .unknown
    }
    return AccessState(status: result.output)
  }

  /// Checks the bundled daemon identity without blocking the caller executor.
  nonisolated public static func daemonAccessStateAsync(
    mainBundleURL: URL
  ) async -> AccessState {
    await Task.detached(priority: .utility) {
      daemonAccessState(mainBundleURL: mainBundleURL)
    }.value
  }

  /// Checks current Input Monitoring permission state without prompting.
  public func checkAccess() -> AccessState {
    Self.currentAccessState()
  }

  /// Requests Input Monitoring permission, showing the system dialog if needed.
  ///
  /// Returns updated state.
  @discardableResult public func requestAccess() -> AccessState {
    IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    let state = checkAccess()
    inputMonitoringState = state
    return state
  }

  /// Start polling permission state every second
  /// for runtime changes.
  public func startPolling() {
    pollingTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: permissionPollNanoseconds)
        guard let self else { break }
        let currentInput = await self.checkAccess()
        let prevInput = await self.inputMonitoringState
        if currentInput != prevInput { await self.updateState(currentInput) }
      }
    }
  }

  /// Stops the background polling task started by ``startPolling()``.
  public func stopPolling() {
    pollingTask?.cancel()
    pollingTask = nil
  }

  private func updateState(_ state: AccessState) {
    let previous = inputMonitoringState
    inputMonitoringState = state
    print("[PermissionManager] Input Monitoring " + "state changed: \(previous) -> \(state)")
  }
}

/// User-facing inventory of privacy and system approvals OJD may invoke.
public struct OJDPermissionRequirement: Sendable, Equatable {
  public let name: String
  public let owner: String
  public let purpose: String
  public let requested: Bool

  public init(name: String, owner: String, purpose: String, requested: Bool) {
    self.name = name
    self.owner = owner
    self.purpose = purpose
    self.requested = requested
  }

  public static let inventory = [
    Self(
      name: "Input Monitoring",
      owner: "OpenJoystickDriver app",
      purpose: "Direct/headless controller input and diagnostics",
      requested: true
    ),
    Self(
      name: "Input Monitoring",
      owner: "OpenJoystickDriver Daemon",
      purpose: "Background physical-controller input",
      requested: true
    ),
    Self(
      name: "Accessibility",
      owner: "None",
      purpose: "OJD does not control other apps or use Accessibility APIs",
      requested: false
    ),
    Self(
      name: "Driver Extension approval",
      owner: "OpenJoystickDriver app",
      purpose: "Optional DriverKit integrity relay; not a TCC privacy permission",
      requested: true
    ),
  ]
}

/// Permission state for the two process identities that must read controller input.
public struct InputMonitoringPermissionSnapshot: Sendable, Equatable {
  /// Input Monitoring state for the menu app/headless executable.
  public let application: PermissionManager.AccessState
  /// Input Monitoring state for the bundled daemon helper.
  public let daemon: PermissionManager.AccessState

  /// Creates a permission snapshot for both process identities.
  public init(
    application: PermissionManager.AccessState,
    daemon: PermissionManager.AccessState
  ) {
    self.application = application
    self.daemon = daemon
  }

  /// True only when both the application and daemon identities have access.
  public var isReady: Bool {
    application == .granted && daemon == .granted
  }
}
