import Foundation
import OpenJoystickDriverKit

/// Removes the main application from login items for the current user.
struct UninstallCommand {
  func run() {
    requireApplicationsBundleOrExit()
    requireValidBundleSignatureOrExit(
      action: CLILocalized.text("cli.login.uninstall_action", "Uninstall")
    )
    do {
      try ApplicationServiceManager.uninstall()
      CLIOutput.stdout(
        CLILocalized.text(
          "cli.login.uninstall_success",
          "Main application removed from login items."
        )
      )
    } catch {
      CLIOutput.error(
        CLILocalized.format(
          "cli.login.uninstall_failed",
          "Could not remove the login item: %@",
          error.localizedDescription
        )
      )
      exit(1)
    }
  }
}
