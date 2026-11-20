import Foundation
package import OpenJoystickDriverKit
import ServiceManagement

/// The main application's login-item registration through `SMAppService`.
package struct MainAppServiceRegistration: ApplicationServiceRegistration {
  /// Creates the registration.
  package init() {}

  /// The state of the main app's login item.
  package var status: ApplicationServiceRegistrationStatus {
    switch SMAppService.mainApp.status {
    case .notRegistered: return .notRegistered
    case .enabled: return .enabled
    case .requiresApproval: return .requiresApproval
    case .notFound: return .notFound
    @unknown default: return .notFound
    }
  }

  /// Registers the main app as a login item.
  ///
  /// - Throws: The `SMAppService` error.
  package func register() throws {
    try SMAppService.mainApp.register()
  }

  /// Removes the main app's login item.
  ///
  /// - Throws: The `SMAppService` error.
  package func unregister() throws {
    try SMAppService.mainApp.unregister()
  }
}
