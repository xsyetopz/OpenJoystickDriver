import Foundation
import OpenJoystickDriverKit

struct CompatibilityCommand {
  func run(arguments: [String]) {
    let usage = CLILocalized.text(
      "cli.compat.usage",
      """
      Usage: OpenJoystickDriver --headless compat show
             OpenJoystickDriver --headless compat set \\
      <generic-hid|sdl2-3|apple-gamecontroller|xbox360-hid>
      """
    )
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
        print(CLILocalized.format("cli.compat.identity", "compatibility identity: %@", id))
      } else {
        print(CLILocalized.text("cli.compat.identity_unknown", "compatibility identity: unknown"))
      }
      return
    }

    guard case .accepted = CompatibilityIdentity.mutationDecision(for: sub) else {
      CLIOutput.error(usage)
      exit(1)
    }

    let ok = runSyncResult {
      do { return try await client.setCompatibilityIdentity(sub) } catch { return false }
    }

    if !ok {
      CLIOutput.error(
        CLILocalized.format(
          "cli.compat.set_failed",
          "Failed to set compatibility identity to %@. "
            + "Launch the installed app and verify Input Monitoring and Accessibility access.",
          sub
        )
      )
      exit(1)
    }

    let status = runSyncResult { try? await client.getStatus() }
    print(
      CLILocalized.format(
        "cli.compat.identity",
        "compatibility identity: %@",
        status?.compatibilityIdentity ?? sub
      )
    )
    if let s = status?.userSpaceVirtualDeviceStatus {
      print(CLILocalized.format("cli.compat.user_space_status", "user-space status: %@", s))
    }
  }
}
