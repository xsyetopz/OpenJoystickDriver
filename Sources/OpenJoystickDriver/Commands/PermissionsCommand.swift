import AppKit
import CoreServices
import Foundation
import OpenJoystickDriverKit

private let inputMonitoringSettingsURL = URL(
  string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
)

func currentInputMonitoringPermissions(
  daemonStatus: String? = nil
) -> InputMonitoringPermissionSnapshot {
  let application = PermissionManager.currentAccessState()
  let daemon =
    daemonStatus.map(PermissionManager.AccessState.init(status:))
    ?? PermissionManager.daemonAccessState(mainBundleURL: Bundle.main.bundleURL)
  return InputMonitoringPermissionSnapshot(application: application, daemon: daemon)
}

func printInputMonitoringPermissions(_ snapshot: InputMonitoringPermissionSnapshot) {
  print("Permissions:")
  print(
    "  App Input Monitoring    : \(snapshot.application.label) \(snapshot.application)"
  )
  print("  Daemon Input Monitoring : \(snapshot.daemon.label) \(snapshot.daemon)")
  print("  Overall                 : " + (snapshot.isReady ? "[OK] ready" : "[ACTION] blocked"))
}

struct PermissionsCommand {
  func run(arguments: [String]) {
    let subcommand = arguments.first ?? "status"
    switch subcommand {
    case "status": printStatus()
    case "request":
      request(arguments: Array(arguments.dropFirst()))
    case "open-settings":
      openInputMonitoringSettings()
    case "explain":
      printPermissionInventory()
    case "refresh":
      refreshInputMonitoring(arguments: Array(arguments.dropFirst()))
    case "--help", "-h", "help":
      printHelp()
    default:
      print("Unknown permissions command: \(subcommand)")
      printHelp()
      exit(1)
    }
  }

  private func printHelp() {
    print(
      """
      Usage: OpenJoystickDriver --headless permissions <command>

      Commands:
        status          Show app and daemon Input Monitoring state
        request app     Request access for the app/headless executable
        request daemon  Request access for the bundled daemon helper
        open-settings   Open the Input Monitoring privacy settings
        explain         Explain every permission OJD may request and why
        refresh --confirm
                        Revoke only OJD Input Monitoring decisions, then re-register the daemon
      """
    )
  }

  private func printStatus() {
    let client = XPCClient()
    client.connect()
    defer { client.disconnect() }
    let payload: XPCStatusPayload? =
      runSyncOptionalResult(timeout: xpcCallTimeoutSeconds) { try? await client.getStatus() }
    let snapshot = currentInputMonitoringPermissions(daemonStatus: payload?.inputMonitoring)

    printInputMonitoringPermissions(snapshot)
    print("")
    print(
      "Daemon state source: "
        + (payload == nil ? "bundled helper probe (daemon XPC unavailable)" : "running daemon XPC")
    )
    printRecoveryHints(for: snapshot)
  }

  private func printPermissionInventory() {
    print("Permission inventory:")
    for requirement in OJDPermissionRequirement.inventory {
      let behavior = requirement.requested ? "may request" : "never requests"
      print("  \(requirement.name) — \(requirement.owner) [\(behavior)]")
      print("    \(requirement.purpose)")
    }
    print("")
    print("OJD never requests Accessibility. If it appears in Accessibility settings,")
    print("it is not required by this build and may be disabled or removed manually.")
  }

  private func refreshInputMonitoring(arguments: [String]) {
    guard arguments == ["--confirm"] else {
      print("This revokes existing Input Monitoring consent for both OJD identities.")
      print("Re-run with: --headless permissions refresh --confirm")
      exit(2)
    }
    requireApplicationsBundleOrExit()
    let identifiers = ["com.openjoystickdriver", "com.openjoystickdriver.daemon"]
    for identifier in identifiers {
      do {
        let result = try BoundedProcessRunner.run(
          executableURL: URL(fileURLWithPath: "/usr/bin/tccutil"),
          arguments: ["reset", "ListenEvent", identifier],
          timeoutSeconds: 5,
          maximumOutputBytes: 65_536
        )
        guard !result.timedOut, result.terminationStatus == 0 else {
          print("ERROR: Could not reset Input Monitoring for \(identifier): \(result.output)")
          exit(1)
        }
        print("Reset Input Monitoring for \(identifier).")
      } catch {
        print("ERROR: Could not reset Input Monitoring for \(identifier): \(error)")
        exit(1)
      }
    }
    do {
      if DaemonManager.isInstalled { try DaemonManager.uninstall() }
      try DaemonManager.install()
      print("Daemon registration refreshed. Request app and daemon access when needed.")
      openInputMonitoringSettings()
    } catch {
      print("ERROR: TCC reset succeeded, but daemon registration failed: \(error)")
      exit(1)
    }
  }

  private func request(arguments: [String]) {
    guard let subject = arguments.first else {
      print("Usage: OpenJoystickDriver --headless permissions request app|daemon")
      exit(1)
    }
    switch subject {
    case "app":
      requestApplicationAccess()
    case "daemon":
      requestDaemonAccess()
    default:
      print("Unknown permission subject: \(subject)")
      print("Usage: OpenJoystickDriver --headless permissions request app|daemon")
      exit(1)
    }
  }

  private func requestApplicationAccess() {
    registerApplicationBundle(Bundle.main.bundleURL)
    MainActor.assumeIsolated {
      let application = NSApplication.shared
      application.setActivationPolicy(.accessory)
      application.activate(ignoringOtherApps: true)
    }

    let manager = PermissionManager()
    let state = runSyncResult {
      var state = await manager.requestAccess()
      for _ in 0..<240 where state == .unknown {
        try? await Task.sleep(nanoseconds: 500_000_000)
        state = await manager.checkAccess()
      }
      return state
    }

    print("App Input Monitoring: \(state.label) \(state)")
    guard state == .granted else {
      print("Access is not granted. Opening System Settings > Privacy > Input Monitoring.")
      openInputMonitoringSettings()
      exit(2)
    }
  }

  private func requestDaemonAccess() {
    requireApplicationsBundleOrExit()
    requireValidBundleSignatureOrExit(action: "Request daemon Input Monitoring")

    let appURL = Bundle.main.bundleURL
    let daemonAppURL = DaemonManager.bundledDaemonApplicationURL(in: appURL)
    let daemonExecutableURL = DaemonManager.bundledDaemonExecutableURL(in: appURL)
    guard FileManager.default.fileExists(atPath: daemonAppURL.path),
      FileManager.default.fileExists(atPath: daemonExecutableURL.path)
    else {
      print("ERROR: Bundled daemon helper is missing at \(daemonAppURL.path).")
      exit(1)
    }

    do {
      if !DaemonManager.isInstalled {
        try DaemonManager.install()
      }
      registerApplicationBundle(appURL)
      registerApplicationBundle(daemonAppURL)
      try launchDaemonPermissionHelper(at: daemonAppURL)
    } catch {
      print("ERROR: Could not launch daemon permission helper: \(error.localizedDescription)")
      exit(1)
    }

    var state = PermissionManager.daemonAccessState(mainBundleURL: appURL)
    for _ in 0..<240 where state == .unknown {
      Thread.sleep(forTimeInterval: 0.5)
      state = PermissionManager.daemonAccessState(mainBundleURL: appURL)
    }

    print("Daemon Input Monitoring: \(state.label) \(state)")
    guard state == .granted else {
      print("Access is not granted. Opening System Settings > Privacy > Input Monitoring.")
      openInputMonitoringSettings()
      exit(2)
    }

    do {
      try DaemonManager.restart()
      print("Daemon restarted with Input Monitoring access.")
    } catch {
      print("ERROR: Access is granted, but daemon restart failed: \(error.localizedDescription)")
      exit(1)
    }
  }

  private func launchDaemonPermissionHelper(at daemonAppURL: URL) throws {
    let result = try BoundedProcessRunner.run(
      executableURL: URL(fileURLWithPath: "/usr/bin/open"),
      arguments: [
        "-n",
        daemonAppURL.path,
        "--args",
        "--request-input-monitoring",
      ],
      timeoutSeconds: 5,
      maximumOutputBytes: 65_536
    )
    guard !result.timedOut, result.terminationStatus == 0 else {
      let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
      let message = result.timedOut
        ? "open timed out after 5 seconds"
        : (detail.isEmpty ? "open failed" : detail)
      throw NSError(
        domain: "OpenJoystickDriver.PermissionsCommand",
        code: Int(result.terminationStatus),
        userInfo: [NSLocalizedDescriptionKey: message]
      )
    }
  }

  private func registerApplicationBundle(_ appURL: URL) {
    guard appURL.pathExtension == "app" else { return }
    let status = LSRegisterURL(appURL as CFURL, true)
    if status != noErr {
      print("WARNING: LaunchServices registration failed for \(appURL.path): \(status)")
    }
  }

  private func openInputMonitoringSettings() {
    if let inputMonitoringSettingsURL, NSWorkspace.shared.open(inputMonitoringSettingsURL) {
      return
    }
    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
  }

  private func printRecoveryHints(for snapshot: InputMonitoringPermissionSnapshot) {
    if snapshot.application != .granted {
      print("App recovery:    --headless permissions request app")
    }
    if snapshot.daemon != .granted {
      print("Daemon recovery: --headless permissions request daemon")
    }
  }
}
