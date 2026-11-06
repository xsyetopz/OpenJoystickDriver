import Foundation

/// The operating system's answer to, and request flow for, the access the driver needs.
///
/// The host platform implements it; ``PermissionManager`` tracks and polls through it.
package protocol AccessControlSystem: Sendable {
  /// Whether this process may read input from physical controllers.
  func inputReadAccessState() -> PermissionManager.AccessState

  /// Whether this process may publish virtual HID devices.
  func inputInjectAccessState() -> PermissionManager.AccessState

  /// Whether this process may post keyboard and pointer events. The system reports only
  /// whether access is granted, so a false answer is `notAuthorized`, not a denial.
  func postEventAccessState() -> RemappingPostEventAccessState

  /// Asks the user for input-read access. Runs on the main actor so the system can register the
  /// application before the settings link opens. The result is read back through
  /// ``inputReadAccessState()``.
  @MainActor
  func requestInputReadAccess()

  /// Asks the user for input-inject access, on the main actor. The result is read back through
  /// ``inputInjectAccessState()``.
  @MainActor
  func requestInputInjectAccess()
}
