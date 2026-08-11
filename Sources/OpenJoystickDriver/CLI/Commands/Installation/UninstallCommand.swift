import Foundation
import OpenJoystickDriverKit

/// Removes the main application from login items for the current user.
struct UninstallCommand {
  func run() {
    requireApplicationsBundleOrExit()
    requireValidBundleSignatureOrExit(action: "Uninstall")
    do {
      try ApplicationServiceManager.uninstall()
      CLIOutput.stdout("Main application removed from login items.")
    } catch {
      CLIOutput.error("Uninstall failed: \(error.localizedDescription)")
      exit(1)
    }
  }
}
