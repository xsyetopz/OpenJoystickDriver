import Foundation
import OpenJoystickDriverKit

struct ListCommand {
  func run() {
    CLIOutput.diagnostic("Scanning for game controllers...")
    CLIOutput.diagnostic("")
    if checkApplicationServiceAndListDevices() { return }
    handleDirectScan()
  }

  private func checkApplicationServiceAndListDevices() -> Bool {
    let client = ApplicationServiceClient()
    client.connect()
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var serviceDevices: [String]?
    Task { @Sendable in
      serviceDevices = try? await client.listDevices()
      semaphore.signal()
    }
    let replied = semaphore.wait(
      timeout: .now() + applicationServiceCallTimeoutSeconds
    ) == .success
    let serviceRunning = replied && serviceDevices != nil

    defer { client.disconnect() }

    guard serviceRunning, let devices = serviceDevices else { return false }
    print("Controllers (from running application service):")
    if devices.isEmpty {
      print("  (none connected)")
    } else {
      for dev in devices { print("  \(dev)") }
    }
    print("")
    return true
  }

  private func handleDirectScan() {
    CLIOutput.diagnostic("(direct scan - application service not running)")
    listUSBDevices()
    CLIOutput.diagnostic("")
    CLIOutput.diagnostic("Note: HID controllers are shown when application service is running.")
  }

  private func listUSBDevices() {
    print("USB Controllers (class 0xFF / GIP):")
    let result: Result<[USBControllerDescription], USBScanFailure> = runSyncResult {
      do {
        return .success(try await USBControllerScanner.scanVendorSpecific())
      } catch {
        return .failure(USBScanFailure(message: error.localizedDescription))
      }
    }
    guard let devices = try? result.get() else {
      if case .failure(let error) = result {
        CLIOutput.error("USB access failed: \(error.message)")
      }
      CLIOutput.diagnostic("Tip: grant the required entitlement and Input Monitoring access.")
      return
    }
    if devices.isEmpty {
      print("  (none found)")
      return
    }
    for device in devices {
      let vid = String(format: "%04X", device.vendorID)
      let pid = String(format: "%04X", device.productID)
      let mappings = device.mappings.isEmpty ? "none" : device.mappings.joined(separator: ",")
      print(
        "  VID=0x\(vid)" + " PID=0x\(pid)" + " bus=\(device.bus)" + " addr=\(device.address)"
          + " parser=\(device.parser)"
          + " protocol=\(device.protocolVariant)"
          + " endpoints=in:0x\(device.inputEndpoint)"
          + " out:0x\(device.outputEndpoint)"
          + " mappings=\(mappings)"
      )
    }
  }
}

private struct USBScanFailure: Error, Sendable {
  let message: String
}
