import Foundation
import OpenJoystickDriverKit

/// Registers the main application to launch at login for the current user.
struct InstallCommand {
  func run() {
    requireApplicationsBundleOrExit()
    requireValidBundleSignatureOrExit(action: "Install")
    do {
      try ApplicationServiceManager.install()
      CLIOutput.stdout("OpenJoystickDriver registered to launch at login.")
    } catch {
      CLIOutput.error("Install failed: \(error.localizedDescription)")
      exit(1)
    }
  }
}
