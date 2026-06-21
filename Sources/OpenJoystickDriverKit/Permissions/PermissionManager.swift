import ApplicationServices
import Foundation
import IOKit
import IOKit.hid

private let permissionPollNanoseconds: UInt64 = 1_000_000_000

/// Manages Input Monitoring permission state for the daemon.
public actor PermissionManager {
  /// The three possible states for a macOS permission.
  public enum AccessState: Sendable, Equatable {
    /// The user has allowed access.
    case granted
    /// The user has denied access, or the system rejected the request.
    case denied
    /// The permission has not been checked yet in this session.
    case unknown

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
  public private(set) var accessibilityState: AccessState = .unknown
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

  nonisolated public static func currentAccessibilityState() -> AccessState {
    AXIsProcessTrusted() ? .granted : .denied
  }

  /// Checks current Input Monitoring permission state without prompting.
  public func checkAccess() -> AccessState { Self.currentAccessState() }

  public func checkAccessibilityAccess() -> AccessState { Self.currentAccessibilityState() }

  /// Requests Input Monitoring permission, showing the system dialog if needed.
  ///
  /// Returns updated state.
  @discardableResult public func requestAccess() -> AccessState {
    IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    let state = checkAccess()
    inputMonitoringState = state
    return state
  }

  @discardableResult public func requestAccessibilityAccess() -> AccessState {
    let options = ["AXTrustedCheckOptionPrompt": true]
    AXIsProcessTrustedWithOptions(options as CFDictionary)
    let state = checkAccessibilityAccess()
    accessibilityState = state
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
        if currentInput != prevInput { await self.updateInputMonitoringState(currentInput) }
        let currentAccessibility = await self.checkAccessibilityAccess()
        let prevAccessibility = await self.accessibilityState
        if currentAccessibility != prevAccessibility {
          await self.updateAccessibilityState(currentAccessibility)
        }
      }
    }
  }

  /// Stops the background polling task started by ``startPolling()``.
  public func stopPolling() {
    pollingTask?.cancel()
    pollingTask = nil
  }

  private func updateInputMonitoringState(_ state: AccessState) {
    let previous = inputMonitoringState
    inputMonitoringState = state
    print("[PermissionManager] Input Monitoring " + "state changed: \(previous) -> \(state)")
  }

  private func updateAccessibilityState(_ state: AccessState) {
    let previous = accessibilityState
    accessibilityState = state
    print("[PermissionManager] Accessibility state changed: \(previous) -> \(state)")
  }
}
