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
      "  DriverKit: value \(payload.driverKitValueEvents), "
        + "report \(payload.driverKitReportEvents)"
    )
    let relayRequirement = payload.driverKitRequired ? "required" : "optional"
    CLIOutput.diagnostic("  DriverKit relay: \(relayRequirement)")
    CLIOutput.diagnostic(
      "  DriverKit relay verdict: \(payload.driverKitRelayVerdict.rawValue.uppercased())"
    )
    if let delta = payload.driverKitInputReportDelta {
      CLIOutput.diagnostic("  DriverKit input report delta: \(delta)")
    }
    if let delta = payload.driverKitSubmissionSuccessDelta {
      CLIOutput.diagnostic("  DriverKit submission success delta: \(delta)")
    }
    if let delta = payload.driverKitSubmissionAttemptDelta {
      CLIOutput.diagnostic("  DriverKit submission attempt delta: \(delta)")
    }
    if let delta = payload.driverKitSubmissionFailureDelta {
      CLIOutput.diagnostic("  DriverKit submission failure delta: \(delta)")
    }
    if let error = payload.driverKitSubmissionLastErrorHex {
      CLIOutput.diagnostic("  DriverKit submission last error: \(error)")
    }
    if let delta = payload.driverKitConnectionAttemptDelta {
      CLIOutput.diagnostic("  DriverKit connection attempt delta: \(delta)")
    }
    if let delta = payload.driverKitConnectionSuccessDelta {
      CLIOutput.diagnostic("  DriverKit connection success delta: \(delta)")
    }
    if let delta = payload.driverKitConnectionFailureDelta {
      CLIOutput.diagnostic("  DriverKit connection failure delta: \(delta)")
    }
    if let error = payload.driverKitLastConnectionErrorHex {
      CLIOutput.diagnostic("  DriverKit connection last error: \(error)")
    }
    if let summary = payload.driverKitDiscoverySummary {
      CLIOutput.diagnostic("  DriverKit discovery: \(summary)")
    }
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
