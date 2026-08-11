import Foundation
import OpenJoystickDriverKit

struct DiagnoseCommand {
  func run(arguments: [String] = []) {
    if let subcommand = arguments.first {
      switch subcommand {
      case "runtime": RuntimeHealthCommand().run(arguments: Array(arguments.dropFirst()))
      case "catalog": GameControllerCatalogCommand().run(arguments: Array(arguments.dropFirst()))
      case "--help", "-h", "help":
        CLIOutput.stdout(
          "Usage: OpenJoystickDriver --headless diagnose " + "[runtime|catalog|report]"
        )
      default:
        CLIOutput.error("Unknown diagnose command: \(subcommand)")
        exit(1)
      }
      return
    }

    CLIOutput.diagnostic("OpenJoystickDriver Diagnostics")
    let divider = String(repeating: "\u{2550}", count: 30)
    CLIOutput.diagnostic(divider)
    CLIOutput.diagnostic("")

    printSystemInfo()
    CLIOutput.diagnostic("")
    printSystemExtensionBundle()
    CLIOutput.diagnostic("")
    printPermissionsSection()
    CLIOutput.diagnostic("")
    printUSBDevices()
    CLIOutput.diagnostic("")
    printTroubleshooting()
  }

  private func printSystemInfo() {
    let ver = ProcessInfo.processInfo.operatingSystemVersion
    CLIOutput.diagnostic("macOS: \(ver.majorVersion).\(ver.minorVersion).\(ver.patchVersion)")
    CLIOutput.diagnostic("Binary: \(CommandLine.arguments[0])")
  }

  private func printSystemExtensionBundle() {
    let appPath = "/Applications/OpenJoystickDriver.app"
    let sysextDir = appPath + "/Contents/Library/SystemExtensions"
    let expectedID = "com.openjoystickdriver.VirtualHIDDevice"
    let expectedDextPath = sysextDir + "/com.openjoystickdriver.VirtualHIDDevice.dext"

    CLIOutput.diagnostic("DriverKit System Extension (in /Applications):")

    let fm = FileManager.default
    guard fm.fileExists(atPath: appPath) else {
      CLIOutput.diagnostic("  App: missing at \(appPath)")
      CLIOutput.diagnostic("  Fix: build + install the app to /Applications")
      return
    }

    CLIOutput.diagnostic("  App: present")
    CLIOutput.diagnostic("  Expected .dext: \(expectedDextPath)")

    guard fm.fileExists(atPath: sysextDir) else {
      CLIOutput.diagnostic("  Result: FAIL (missing SystemExtensions folder)")
      CLIOutput.diagnostic("  Fix: run: ./scripts/ojd rebuild dev")
      return
    }

    let items = (try? fm.contentsOfDirectory(atPath: sysextDir)) ?? []
    let dexts = items.filter { $0.hasSuffix(".dext") }.sorted()
    if dexts.isEmpty {
      CLIOutput.diagnostic("  Result: FAIL (no .dext bundles found)")
      CLIOutput.diagnostic("  Fix: run: ./scripts/ojd build dext")
      return
    }

    CLIOutput.diagnostic("  Found .dext bundles:")
    var foundExpected = false
    for d in dexts {
      let path = sysextDir + "/" + d
      let bid = Bundle(path: path)?.bundleIdentifier ?? "UNKNOWN"
      CLIOutput.diagnostic("    - \(d) (id: \(bid))")
      if bid == expectedID { foundExpected = true }
    }

    if foundExpected {
      CLIOutput.diagnostic("  Result: PASS (expected id present: \(expectedID))")
    } else {
      CLIOutput.diagnostic("  Result: FAIL (expected id missing: \(expectedID))")
      CLIOutput.diagnostic("  Fix: run: ./scripts/ojd build dext")
    }
  }

  private func printPermissionsSection() {
    let client = ApplicationServiceClient()
    client.connect()
    defer { client.disconnect() }
    let payload: ApplicationServiceStatusPayload? = runSyncOptionalResult(
      timeout: applicationServiceCallTimeoutSeconds
    ) { try? await client.getStatus() }
    guard let payload else {
      CLIOutput.diagnostic("Permissions: unavailable without the running main app")
      CLIOutput.diagnostic("  Recovery: launch the installed OpenJoystickDriver app")
      return
    }

    permissionSnapshotLines(
      StatusPermissions(
        inputMonitoring: payload.inputMonitoring,
        accessibility: payload.accessibility
      )
    ).forEach { CLIOutput.diagnostic($0) }
    CLIOutput.diagnostic("  State source     : running main app")
  }

  private func printUSBDevices() {
    CLIOutput.diagnostic("USB Game Controllers (class 0xFF):")
    let result: Result<[USBControllerDescription], DiagnoseUSBScanFailure> = runSyncResult {
      do { return .success(try await USBControllerScanner.scanVendorSpecific()) } catch {
        return .failure(DiagnoseUSBScanFailure(message: error.localizedDescription))
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
      CLIOutput.diagnostic("  (none detected)")
      return
    }
    for device in devices {
      let vid = String(format: "%04X", device.vendorID)
      let pid = String(format: "%04X", device.productID)
      CLIOutput.diagnostic(
        "  VID=0x\(vid)" + " PID=0x\(pid)" + " bus=\(device.bus)" + " addr=\(device.address)"
      )
    }
  }

  private func printTroubleshooting() {
    CLIOutput.diagnostic("Troubleshooting:")
    CLIOutput.diagnostic("  No input from controller?")
    CLIOutput.diagnostic(
      "    -> Grant Input Monitoring: System Settings -> Privacy & Security"
        + " -> Input Monitoring"
    )
    CLIOutput.diagnostic("  User-space virtual device unavailable?")
    CLIOutput.diagnostic("    -> Grant Accessibility to OpenJoystickDriver in Privacy & Security")
    CLIOutput.diagnostic("  DriverKit extension missing/broken?")
    CLIOutput.diagnostic("    -> Run: ./scripts/ojd rebuild dev")
    CLIOutput.diagnostic("  Reporting a controller issue?")
    CLIOutput.diagnostic("    -> Run: --headless diagnose report")
  }
}

private struct DiagnoseUSBScanFailure: Error, Sendable { let message: String }
