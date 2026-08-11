import Foundation
import OpenJoystickDriverKit
import Security

/// Determines whether the current signed host requires DriverKit relay proof.
enum DriverKitRelayRequirement {
  static let entitlement = "com.apple.developer.driverkit.userclient-access"

  static func currentExecutableRequiresRelay() -> Bool {
    guard let task = SecTaskCreateFromSelf(nil) else { return false }
    let value = SecTaskCopyValueForEntitlement(task, entitlement as CFString, nil)
    return requiresRelay(userClientAccess: value)
  }

  static func requiresRelay(userClientAccess value: CFTypeRef?) -> Bool {
    guard let allowedBundleIdentifiers = value as? [String] else { return false }
    return allowedBundleIdentifiers.contains(DriverKitRelayIdentity.bundleIdentifier)
  }
}
