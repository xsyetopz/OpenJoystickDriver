import Foundation
import OpenJoystickDriverKit

/// Removes the main application from login items for the current user.
struct UninstallCommand {
  func run() {
    requireApplicationsBundleOrExit()
    requireValidBundleSignatureOrExit(action: "Uninstall")
    do {
      try ApplicationServiceManager.uninstall()
      print("Main application removed from login items.")
    } catch {
      print("Uninstall failed: \(error.localizedDescription)")
      exit(1)
    }
  }
}
