import AppKit
import Foundation
import OpenJoystickDriverKit

func printPermissionSnapshot(_ permissions: StatusPermissions) {
  permissionSnapshotLines(permissions).forEach { print($0) }
}

func printPermissionSnapshot(_ snapshot: PermissionManager.Snapshot) {
  printPermissionSnapshot(StatusPermissions(snapshot))
}

func permissionSnapshotLines(_ permissions: StatusPermissions) -> [String] {
  RuntimeStatusText.permissionLines(permissions)
}

struct PermissionsCommand {
  func run(arguments: [String]) {
    switch arguments.first ?? "status" {
    case "status": printStatus()
    case "request": requestAccess(arguments: Array(arguments.dropFirst()))
    case "open": openSettings(arguments: Array(arguments.dropFirst()))
    case "explain": printPermissionInventory()
    case "--help", "-h", "help": printHelp()
    case let command:
      CLIOutput.error("Unknown permissions command: \(command)")
      printHelp()
      exit(1)
    }
  }

  private func printHelp() {
    print(
      """
      Usage: OpenJoystickDriver --headless permissions <command>

      Commands:
        status                     Show the main app permission states
        request                    Request required permissions for the main app
        open [input|output]
                                   Open Input Monitoring or Accessibility
        explain                    Explain every permission OJD may request
      """
    )
  }

  private func connectedClient() -> ApplicationServiceClient {
    let client = ApplicationServiceClient()
    client.connect()
    guard client.isConnected else {
      CLIOutput.error(
        "Could not connect to the installed main app. Launch it manually, then verify "
          + "Input Monitoring and Accessibility access."
      )
      exit(1)
    }
    return client
  }

  private func printStatus() {
    let client = ApplicationServiceClient()
    client.connect()
    defer { client.disconnect() }
    let result: ApplicationServiceStatusPayload? = runSyncOptionalResult(
      timeout: applicationServiceCallTimeoutSeconds
    ) { try? await client.getStatus() }
    guard let payload = result else {
      printPermissionSnapshot(localPermissionSnapshot())
      CLIOutput.diagnostic("")
      CLIOutput.diagnostic("State source: local system (main app did not return status)")
      CLIOutput.diagnostic("Recovery: launch the installed OpenJoystickDriver app")
      exit(1)
    }

    let status = RuntimeStatusSnapshot(payload: payload)
    printPermissionSnapshot(status.permissions)
    CLIOutput.diagnostic("")
    CLIOutput.diagnostic("State source: running main app")
    if !status.permissions.isReady {
      CLIOutput.diagnostic("Recovery: run --headless permissions request")
    }
  }

  private func localPermissionSnapshot() -> PermissionManager.Snapshot {
    PermissionManager.Snapshot(
      inputMonitoring: PermissionManager.currentInputMonitoringAccessState(),
      accessibility: PermissionManager.currentAccessibilityAccessState()
    )
  }

  private func printPermissionInventory() {
    print("Permission inventory:")
    for requirement in OJDPermissionRequirement.inventory {
      let behavior = requirement.requested ? "may request" : "never requests"
      print("  \(requirement.name) - \(requirement.owner) [\(behavior)]")
      print("    \(requirement.purpose)")
    }
  }

  private func requestAccess(arguments: [String]) {
    guard arguments.isEmpty else {
      CLIOutput.error("Usage: OpenJoystickDriver --headless permissions request")
      exit(1)
    }
    let client = connectedClient()
    defer { client.disconnect() }
    let result: PermissionManager.Snapshot? = runSyncOptionalResult(timeout: 10) {
      try? await client.requestRequiredAccess()
    }
    guard let snapshot = result else {
      CLIOutput.error(
        "The main app did not return permission status. Launch it manually and retry."
      )
      exit(1)
    }
    printPermissionSnapshot(snapshot)
    guard snapshot.isReady else {
      CLIOutput.error(
        "Required access is blocked. Grant Input Monitoring and Accessibility in "
          + "System Settings > Privacy & Security, then retry."
      )
      if snapshot.inputMonitoring != .granted {
        openPermissionSettings(kind: "input")
      } else {
        openPermissionSettings(kind: "output")
      }
      exit(2)
    }
  }

  private func openSettings(arguments: [String]) {
    guard arguments.count <= 1 else {
      CLIOutput.error("Usage: OpenJoystickDriver --headless permissions open [input|output]")
      exit(1)
    }
    openPermissionSettings(kind: arguments.first ?? "input")
  }

  private func openPermissionSettings(kind: String) {
    let pane: String
    switch kind {
    case "input": pane = "Privacy_ListenEvent"
    case "output": pane = "Privacy_Accessibility"
    default:
      CLIOutput.error("Unknown permission kind: \(kind)")
      exit(1)
    }
    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
    if let url, NSWorkspace.shared.open(url) { return }
    CLIOutput.warning("Could not open the requested privacy pane; opening System Settings.")
    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
  }
}
