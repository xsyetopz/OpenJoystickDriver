import Foundation
import OpenJoystickDriverKit

struct ResetSettingsCommand {
  func run() {
    let client = ApplicationServiceClient()
    client.connect()
    defer { client.disconnect() }

    let ok =
      runSyncResult { do { return try await client.resetSettings() } catch { return false } }
      ?? false

    if !ok {
      CLIOutput.error(
        "Failed to reset settings. Launch the installed app and verify its permissions."
      )
      exit(1)
    }

    print("OK: reset application service settings.")
    print("Next: run compat set <identity> to choose the compatibility identity.")
  }
}
