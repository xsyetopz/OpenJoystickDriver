import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverUSB

struct ListCommand {
  func run() {
    CLIOutput.diagnostic(
      CLILocalized.text("cli.controller.scanning", "Scanning for game controllers...")
    )
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
    let replied = semaphore.wait(timeout: .now() + applicationServiceCallTimeoutSeconds) == .success
    let serviceRunning = replied && serviceDevices != nil

    defer { client.disconnect() }

    guard serviceRunning, let devices = serviceDevices else { return false }
    print(
      CLILocalized.text(
        "cli.controller.serviceControllers",
        "Controllers (from running application service):"
      )
    )
    if devices.isEmpty {
      print("  \(CLILocalized.text("cli.controller.noneConnected", "(none connected)"))")
    } else {
      for dev in devices { print("  \(dev)") }
    }
    print("")
    return true
  }

  private func handleDirectScan() {
    CLIOutput.diagnostic(
      CLILocalized.text(
        "cli.controller.directScan",
        "(direct scan - application service not running)"
      )
    )
    listUSBDevices()
    CLIOutput.diagnostic("")
    CLIOutput.diagnostic(
      CLILocalized.text(
        "cli.controller.hidNote",
        "Note: HID controllers are shown when application service is running."
      )
    )
  }

  private func listUSBDevices() {
    print(CLILocalized.text("cli.controller.usbControllers", "USB Controllers (class 0xFF / GIP):"))
    let result: Result<[USBControllerDescription], USBScanFailure> = runSyncResult {
      do {
        return .success(
          try await USBControllerScanner.scanVendorSpecific(
            using: OpenJoystickDriverUSBTransportProvider()
          )
        )
      } catch { return .failure(USBScanFailure(message: error.localizedDescription)) }
    }
    guard let devices = try? result.get() else {
      if case .failure(let error) = result {
        CLIOutput.error(
          CLILocalized.format(
            "cli.controller.usbAccessFailed",
            "USB access failed: %@",
            error.message
          )
        )
      }
      CLIOutput.diagnostic(
        CLILocalized.text(
          "cli.controller.usbAccessTip",
          "Tip: grant the required entitlement and Input Monitoring access."
        )
      )
      return
    }
    if devices.isEmpty {
      print("  \(CLILocalized.text("cli.controller.noneFound", "(none found)"))")
      return
    }
    for device in devices {
      let vid = String(format: "%04X", device.vendorID)
      let pid = String(format: "%04X", device.productID)
      let quirks = device.quirks.isEmpty ? "none" : device.quirks.joined(separator: ",")
      print(
        "  VID=0x\(vid)" + " PID=0x\(pid)" + " bus=\(device.bus)" + " addr=\(device.address)"
          + " parser=\(device.parser)" + " protocol=\(device.protocolVariant)"
          + " endpoints=in:0x\(device.inputEndpoint)" + " out:0x\(device.outputEndpoint)"
          + " quirks=\(quirks)"
      )
    }
  }
}

private struct USBScanFailure: Error, Sendable { let message: String }
