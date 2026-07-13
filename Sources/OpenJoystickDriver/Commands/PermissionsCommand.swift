import AppKit
import Foundation
import OpenJoystickDriverKit

func permissionSnapshot(
  inputMonitoring: String,
  accessibility: String
) -> PermissionManager.Snapshot {
  PermissionManager.Snapshot(
    inputMonitoring: PermissionManager.AccessState(status: inputMonitoring),
    accessibility: PermissionManager.AccessState(status: accessibility)
  )
}

func printPermissionSnapshot(_ snapshot: PermissionManager.Snapshot) {
  print("Permissions:")
  print("  Input Monitoring : \(snapshot.inputMonitoring.label) \(snapshot.inputMonitoring)")
  print("  Accessibility    : \(snapshot.accessibility.label) \(snapshot.accessibility)")
  print("  Overall          : " + (snapshot.isReady ? "[OK] ready" : "[ACTION] blocked"))
}

struct PermissionsCommand {
  func run(arguments: [String]) {
    switch arguments.first ?? "status" {
    case "status": printStatus()
    case "request": requestAccess(arguments: Array(arguments.dropFirst()))
    case "open-settings": openSettings(arguments: Array(arguments.dropFirst()))
    case "explain": printPermissionInventory()
    case "--help", "-h", "help": printHelp()
    case let command:
      print("Unknown permissions command: \(command)")
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
        open-settings [input|output]
                                   Open Input Monitoring or Accessibility
        explain                    Explain every permission OJD may request
      """
    )
  }

  private func connectedClient() -> ApplicationServiceClient {
    let client = ApplicationServiceClient()
    client.connect()
    guard client.isConnected else {
      print("ERROR: Could not connect to the installed main app.")
      exit(1)
    }
    return client
  }

  private func printStatus() {
    let client = connectedClient()
    defer { client.disconnect() }
    let result: ApplicationServiceStatusPayload? = runSyncOptionalResult(
      timeout: applicationServiceCallTimeoutSeconds
    ) {
      try? await client.getStatus()
    }
    guard let payload = result else {
      print("ERROR: The main app did not return permission status.")
      exit(1)
    }

    printPermissionSnapshot(
      permissionSnapshot(
        inputMonitoring: payload.inputMonitoring,
        accessibility: payload.accessibility
      )
    )
    print("")
    print("State source: running main app")
    if !permissionSnapshot(
      inputMonitoring: payload.inputMonitoring,
      accessibility: payload.accessibility
    ).isReady {
      print("Recovery: --headless permissions request")
    }
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
      print("Usage: OpenJoystickDriver --headless permissions request")
      exit(1)
    }
    let client = connectedClient()
    defer { client.disconnect() }
    let result: PermissionManager.Snapshot? = runSyncOptionalResult(timeout: 10) {
      try? await client.requestRequiredAccess()
    }
    guard let snapshot = result else {
      print("ERROR: The main app did not return permission status.")
      exit(1)
    }
    printPermissionSnapshot(snapshot)
    guard snapshot.isReady else {
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
      print("Usage: OpenJoystickDriver --headless permissions open-settings [input|output]")
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
      print("Unknown permission kind: \(kind)")
      exit(1)
    }
    let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
    )
    if let url, NSWorkspace.shared.open(url) { return }
    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
  }
}
