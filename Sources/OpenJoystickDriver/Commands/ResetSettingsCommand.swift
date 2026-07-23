import Foundation
import OpenJoystickDriverKit

struct ResetSettingsCommand {
  func run() {
    let client = ApplicationServiceClient()
    client.connect()

    let ok = runSyncResult {
      do {
        return try await client.resetSettings()
      } catch {
        return false
      }
    } ?? false

    if !ok {
      print("ERROR: failed to reset settings (application service not running?)")
      exit(1)
    }

    print("OK: reset application service settings.")
    print("Next: run compatibility set <identity> to choose the compatibility identity.")
  }
}
