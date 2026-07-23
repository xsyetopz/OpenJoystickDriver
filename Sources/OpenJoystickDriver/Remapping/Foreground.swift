import AppKit
import OpenJoystickDriverKit

/// Reads the exact bundle identifier of the current foreground application.
protocol RemappingForegroundApplicationProviding: Sendable {
  func frontmostBundleIdentifier() -> String?
}

/// Reads the current foreground application on demand without owning a polling loop.
struct WorkspaceRemappingForegroundApplication: RemappingForegroundApplicationProviding {
  func frontmostBundleIdentifier() -> String? {
    NSWorkspace.shared.frontmostApplication?.bundleIdentifier
  }
}

/// Reads the authorization required to synthesize keyboard and pointer events.
protocol RemappingPostEventAccessProviding: Sendable {
  func currentState() -> RemappingPostEventAccessState
}

extension CoreGraphicsPostEventAccess: RemappingPostEventAccessProviding {}

enum RemappingForegroundPolicy {
  static func eligibility(
    for scope: RemappingApplicationScope,
    frontmostBundleIdentifier: String?,
    accessState: RemappingPostEventAccessState,
    outputSuppressed: Bool
  ) -> RemappingRouteEligibility {
    guard !outputSuppressed else { return .outputSuppressed }
    guard accessState == .granted else { return .postEventAccessNotAuthorized }
    switch scope {
    case .global:
      return .eligible
    case .application(let requiredBundleIdentifier):
      return frontmostBundleIdentifier == requiredBundleIdentifier
        ? .eligible : .targetApplicationNotFrontmost
    }
  }
}
