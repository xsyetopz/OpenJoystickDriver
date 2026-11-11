import AppKit
import OpenJoystickDriverKit

/// Reads the exact bundle identifier of the current foreground application.
protocol RemappingForegroundApplicationProviding: Sendable {
  /// Returns the bundle identifier of the foreground application, or nil when it is not known.
  func frontmostAppID() -> String?
}

// `@unchecked Sendable` only because of `observerToken`: it is written once in `init` and read
// in `deinit`, so no other thread touches it. The bundle identifier is behind `Locked`.
/// Tracks the foreground application from workspace activation notifications.
///
/// Remapping routing reads the frontmost application for every dispatched input batch, so the
/// tracker keeps it in memory instead of querying `NSWorkspace` each time.
final class WorkspaceRemappingForegroundApplication: RemappingForegroundApplicationProviding,
  @unchecked Sendable
{
  /// The center that posts the workspace notifications.
  private let notificationCenter: NotificationCenter
  /// The bundle identifier of the foreground application.
  private let appID = Locked<String?>(nil)
  /// The token of the activation observer.
  private var observerToken: any NSObjectProtocol?

  /// Creates the tracker, which observes the activation of applications.
  init(notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter) {
    self.notificationCenter = notificationCenter
    // Observe before the first read so an activation between the two is not lost.
    observerToken = notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: nil
    ) { [weak self] notification in
      let application =
        notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
      self?.update(application?.bundleIdentifier)
    }
    let initial = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    appID.withLock { if $0 == nil { $0 = initial } }
  }

  deinit { observerToken.map(notificationCenter.removeObserver) }

  /// Returns the bundle identifier of the foreground application, or nil when it is not known.
  func frontmostAppID() -> String? { appID.withLock { $0 } }

  /// Stores `appID` as the foreground application.
  private func update(_ appID: String?) {
    self.appID.withLock { $0 = appID }
  }
}

/// Reads the authorization required to synthesize keyboard and pointer events.
protocol RemappingPostEventAccessProviding: Sendable {
  /// Returns the current post-event access state.
  func currentState() -> RemappingPostEventAccessState
}

extension CoreGraphicsPostEventAccess: RemappingPostEventAccessProviding {}

/// Decides whether a route may emit, from the application scope, the frontmost application and the
/// post-event access.
enum RemappingForegroundPolicy {
  /// Returns why a route emits or not.
  ///
  /// Suppressed output wins, then missing post-event access when the profile needs it, then the
  /// application scope.
  static func eligibility(
    for scope: RemappingApplicationScope,
    frontmostAppID: String?,
    accessState: RemappingPostEventAccessState,
    outputSuppressed: Bool,
    requiresPostEventAccess: Bool = true
  ) -> RemappingRouteEligibility {
    guard !outputSuppressed else { return .outputSuppressed }
    guard !requiresPostEventAccess || accessState == .granted else {
      return .postEventAccessNotAuthorized
    }
    switch scope {
    case .global: return .eligible
    case .application(let requiredAppIDs):
      return frontmostAppID.map(requiredAppIDs.contains) == true
        ? .eligible : .targetApplicationNotFrontmost
    }
  }
}
