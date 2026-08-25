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
        "Virtual-device test failed. Launch the installed app and verify Input Monitoring "
          + "and Accessibility access."
      )
      exit(1)
    }

    CLIOutput.diagnostic("Virtual device test (\(payload.seconds)s)")
    CLIOutput.diagnostic(
      "  User-space: value \(payload.userSpaceValueEvents), report \(payload.userSpaceReportEvents)"
    )
    if payload.userSpaceRequired {
      CLIOutput.diagnostic("  User-space status: \(payload.userSpaceStatus)")
      CLIOutput.diagnostic(
        "  User-space verdict: \(payload.userSpaceVerdict.rawValue.uppercased())"
      )
    }
    if !payload.isSuccessful { exit(1) }
  }
}
