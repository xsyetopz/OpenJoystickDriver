import Foundation
import OpenJoystickDriverKit

struct CompatibilityCommand {
  func run(arguments: [String]) {
    let usage = """
      Usage: OpenJoystickDriver --headless compat show
             OpenJoystickDriver --headless compat set \
      <generic-hid|sdl2-3|apple-gamecontroller|x360-hid|xone-hid>
      """
    guard let sub = arguments.first else {
      print(usage)
      return
    }

    let client = ApplicationServiceClient()
    client.connect()
    defer { client.disconnect() }

    if sub == "status" {
      let status = runSyncResult { try? await client.getStatus() }
      if let id = status?.compatibilityIdentity {
        print("compatibility identity: \(id)")
      } else {
        print("compatibility identity: unknown")
      }
      return
    }

    guard CompatibilityIdentity(rawValue: sub) != nil else {
      CLIOutput.error(usage)
      exit(1)
    }

    let ok = runSyncResult {
      do {
        try await client.setCompatibilityIdentity(sub)
        return true
      } catch { return false }
    }

    if !ok {
      CLIOutput.error(
        "Failed to set compatibility identity to \(sub). "
          + "Launch the installed app and verify Input Monitoring and Accessibility access."
      )
      exit(1)
    }

    let status = runSyncResult { try? await client.getStatus() }
    print("compatibility identity: \(status?.compatibilityIdentity ?? sub)")
    if let s = status?.userSpaceVirtualDeviceStatus { print("user-space status: \(s)") }
  }
}
