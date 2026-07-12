import Foundation
import OpenJoystickDriverKit

struct StatusCommand {
  func run() {
    printHeader()
    let client = XPCClient()
    client.connect()
    let semaphore = DispatchSemaphore(value: 0)
    // nonisolated(unsafe): semaphore ensures sequential access - no data race.
    nonisolated(unsafe) var xpcPayload: XPCStatusPayload?
    Task { @Sendable in
      xpcPayload = try? await client.getStatus()
      semaphore.signal()
    }
    let connected =
      semaphore.wait(timeout: .now() + xpcCallTimeoutSeconds) == .success && xpcPayload != nil

    if connected, let payload = xpcPayload {
      printPayloadStatus(payload)
    } else {
      client.disconnect()
      runDirectMode()
    }
    print("")
    printUsageHint()
  }

  private func printHeader() {
    print("OpenJoystickDriver Status")
    let divider = String(repeating: "\u{2500}", count: 25)
    print(divider)
    print("")
  }

  private func printPayloadStatus(_ payload: XPCStatusPayload) {
    print("(connected to running daemon via XPC)")
    print("")
    let permissions = currentInputMonitoringPermissions(
      daemonStatus: payload.inputMonitoring
    )
    printInputMonitoringPermissions(permissions)
    print("")
    if let mode = payload.virtualDeviceMode {
      print("Virtual device mode:")
      print("  requested : \(mode)")
      if let output = payload.effectiveOutputMode {
        print("  output    : \(output)")
      }
      if let id = payload.compatibilityIdentity {
        print("  identity  : \(id)")
      }
      if let enabled = payload.userSpaceVirtualDeviceEnabled {
        let s = enabled ? "enabled" : "disabled"
        print("  user-space: \(s)")
      }
      if let s = payload.userSpaceVirtualDeviceStatus {
        print("  status    : \(s)")
      }
      print("")
    }
    if payload.connectedDevices.isEmpty {
      print("Devices: (none connected)")
    } else {
      print("Devices" + " (\(payload.connectedDevices.count)):")
      for dev in payload.connectedDevices {
        let sn = dev.serialNumber ?? "none"
        let vid = dev.vendorID
        let pid = dev.productID
        print(
          "  \(dev.name)" + " (VID:\(vid) PID:\(pid)" + " \(dev.parser) [\(dev.connection)]"
            + " SN:\(sn))"
        )
        let mappings = dev.mappingFlags.isEmpty ? "none" : dev.mappingFlags.joined(separator: ",")
        let backends =
          dev.preferredBackends.isEmpty ? "none" : dev.preferredBackends.joined(separator: ",")
        print(
          "    protocol=\(dev.protocolVariant)"
            + " endpoints=in:0x\(String(dev.inputEndpoint, radix: 16))"
            + " out:0x\(String(dev.outputEndpoint, radix: 16))"
            + " setConfig=\(dev.needsSetConfiguration)"
            + " settleMs=\(dev.postHandshakeSettleMs)"
        )
        print("    mappings=\(mappings) backends=\(backends)")
        let motors = dev.physicalOutputCapabilities.rumbleMotors.map(\.rawValue)
        let lighting = dev.physicalOutputCapabilities.lightingFeatures.map(\.rawValue)
        let binaryMotors = dev.physicalOutputCapabilities.binaryRumbleMotors.map(\.rawValue)
        print(
          "    physical-output motors=\(motors.isEmpty ? "none" : motors.joined(separator: ","))"
            + " lighting=\(lighting.isEmpty ? "none" : lighting.joined(separator: ","))"
            + " binary=\(binaryMotors.isEmpty ? "none" : binaryMotors.joined(separator: ","))"
            + " evidence=\(dev.physicalOutputCapabilities.evidence.rawValue)"
        )
      }
    }
  }

  private func printUsageHint() { print("Use '--headless list'" + " to enumerate controllers.") }

  private func runDirectMode() {
    print("(direct mode - daemon not running)")
    print("")
    let permissions = currentInputMonitoringPermissions()
    printInputMonitoringPermissions(permissions)
    if permissions.application != .granted {
      print("  -> App recovery: --headless permissions request app")
    }
    if permissions.daemon != .granted {
      print("  -> Daemon recovery: --headless permissions request daemon")
    }
  }
}
