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

    let payload = runSyncResult { try? await client.runVirtualDeviceSelfTest(seconds: seconds) }
    guard let payload else {
      print("ERROR: self-test failed (application service not running?)")
      exit(1)
    }

    print("Virtual device self-test (\(payload.seconds)s)")
    print(
      "  DriverKit: value \(payload.driverKitValueEvents), "
        + "report \(payload.driverKitReportEvents)"
    )
    let relayRequirement = payload.driverKitRequired ? "required" : "optional"
    print("  DriverKit relay: \(relayRequirement)")
    print("  DriverKit relay verdict: \(payload.driverKitRelayVerdict.rawValue.uppercased())")
    if let delta = payload.driverKitInputReportDelta {
      print("  DriverKit input report delta: \(delta)")
    }
    if let delta = payload.driverKitSubmissionSuccessDelta {
      print("  DriverKit submission success delta: \(delta)")
    }
    if let delta = payload.driverKitSubmissionAttemptDelta {
      print("  DriverKit submission attempt delta: \(delta)")
    }
    if let delta = payload.driverKitSubmissionFailureDelta {
      print("  DriverKit submission failure delta: \(delta)")
    }
    if let error = payload.driverKitSubmissionLastErrorHex {
      print("  DriverKit submission last error: \(error)")
    }
    if let delta = payload.driverKitConnectionAttemptDelta {
      print("  DriverKit connection attempt delta: \(delta)")
    }
    if let delta = payload.driverKitConnectionSuccessDelta {
      print("  DriverKit connection success delta: \(delta)")
    }
    if let delta = payload.driverKitConnectionFailureDelta {
      print("  DriverKit connection failure delta: \(delta)")
    }
    if let error = payload.driverKitLastConnectionErrorHex {
      print("  DriverKit connection last error: \(error)")
    }
    if let summary = payload.driverKitDiscoverySummary {
      print("  DriverKit discovery: \(summary)")
    }
    print(
      "  User-space: value \(payload.userSpaceValueEvents), report \(payload.userSpaceReportEvents)"
    )
    if payload.userSpaceRequired {
      print("  User-space status: \(payload.userSpaceStatus)")
      print("  User-space verdict: \(payload.userSpaceVerdict.rawValue.uppercased())")
    }
    if !payload.isSuccessful { exit(1) }
  }
}
