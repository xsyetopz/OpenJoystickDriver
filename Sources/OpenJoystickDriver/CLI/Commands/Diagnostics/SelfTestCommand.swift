import Foundation
import OpenJoystickDriverKit

struct SelfTestCommand {
  func run(arguments: [String]) {
    let seconds: Int
    if let first = arguments.first, let parsed = Int(first), parsed > 0 {
      seconds = parsed
    } else {
      seconds = 5
    }

    let client = ApplicationServiceClient()
    client.connect()
    defer { client.disconnect() }

    let payload = withCLIShutdownCleanup(
      { client.disconnect() },
      { runSyncResult { try? await client.runVirtualDeviceSelfTest(seconds: seconds) } }
    )
    guard let payload else {
      CLIOutput.error(
        CLILocalized.text(
          "cli.test.failed",
          "The virtual-device test failed. Launch the installed app, then verify Input "
            + "Monitoring and Accessibility access."
        )
      )
      exit(1)
    }

    CLIOutput.diagnostic(
      CLILocalized.format("cli.test.heading", "Virtual device test (%ds)", payload.seconds)
    )
    CLIOutput.diagnostic(
      CLILocalized.format(
        "cli.test.userspace_events",
        "  User-space: value %d, report %d",
        payload.userSpaceValueEvents,
        payload.userSpaceReportEvents
      )
    )
    if payload.userSpaceRequired {
      CLIOutput.diagnostic(
        CLILocalized.format(
          "cli.test.userspace_status",
          "  User-space status: %@",
          payload.userSpaceStatus
        )
      )
      CLIOutput.diagnostic(
        CLILocalized.format(
          "cli.test.userspace_verdict",
          "  User-space verdict: %@",
          payload.userSpaceVerdict.rawValue.uppercased()
        )
      )
    }
    if !payload.isSuccessful { exit(1) }
  }
}
