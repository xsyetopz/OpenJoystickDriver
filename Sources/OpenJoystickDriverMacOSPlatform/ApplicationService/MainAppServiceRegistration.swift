import Foundation
import OpenJoystickDriverKit
import ServiceManagement

/// The main application's login-item registration through `SMAppService`.
package struct MainAppServiceRegistration: ApplicationServiceRegistration {
  /// Creates the registration.
  package init() {}

  /// The state of the main app's login item, `notFound` before macOS 13.
  package var status: ApplicationServiceRegistrationStatus {
    guard #available(macOS 13.0, *) else { return .notFound }
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
  /// - Throws: ``ApplicationServiceManager/ManagerError/unsupportedOperatingSystem`` before macOS
  ///   13, and the `SMAppService` error otherwise.
  package func register() throws {
    guard #available(macOS 13.0, *) else {
      throw ApplicationServiceManager.ManagerError.unsupportedOperatingSystem
    }
    try SMAppService.mainApp.register()
  }

  /// Removes the main app's login item.
  ///
  /// - Throws: ``ApplicationServiceManager/ManagerError/unsupportedOperatingSystem`` before macOS
  ///   13, and the `SMAppService` error otherwise.
  package func unregister() throws {
    guard #available(macOS 13.0, *) else {
      throw ApplicationServiceManager.ManagerError.unsupportedOperatingSystem
    }
    try SMAppService.mainApp.unregister()
  }
}
