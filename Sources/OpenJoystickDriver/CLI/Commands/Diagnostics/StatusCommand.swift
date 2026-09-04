import Foundation
import OpenJoystickDriverKit

struct StatusCommand {
  func run(arguments: [String] = []) {
    guard arguments.isEmpty || arguments == ["--json"] else {
      CLIOutput.error(
        CLILocalized.text("cli.status.json_only", "status accepts only --json.")
      )
      exit(CLIParseError.exitCode)
    }
    let json = arguments.contains("--json")
    if !json { printHeader() }
    let client = ApplicationServiceClient()
    client.connect(timeoutSeconds: applicationServiceCallTimeoutSeconds)
    let semaphore = DispatchSemaphore(value: 0)
    // nonisolated(unsafe): semaphore ensures sequential access - no data race.
    nonisolated(unsafe) var servicePayload: ApplicationServiceStatusPayload?
    Task { @Sendable in
      servicePayload = try? await client.getStatus()
      semaphore.signal()
    }
    let replied = semaphore.wait(timeout: .now() + applicationServiceCallTimeoutSeconds) == .success
    let connected = replied && servicePayload != nil

    if connected, let payload = servicePayload {
      if json { printJSON(payload) } else { printPayloadStatus(payload) }
    } else {
      client.disconnect()
      if json { printJSON(directPayload()) } else { runDirectMode() }
    }
    if !json {
      print("")
      printUsageHint()
    }
  }

  private func printHeader() {
    print(CLILocalized.text("cli.status.heading", "OpenJoystickDriver Status"))
    let divider = String(repeating: "\u{2500}", count: 25)
    print(divider)
    print("")
  }

  private func printPayloadStatus(_ payload: ApplicationServiceStatusPayload) {
    RuntimeStatusText.payloadLines(RuntimeStatusSnapshot(payload: payload)).forEach { print($0) }
  }

  private func printUsageHint() {
    print(
      CLILocalized.text(
        "cli.status.usage_hint",
        "Use '--headless controller list' to enumerate controllers."
      )
    )
  }

  private func runDirectMode() {
    RuntimeStatusText.directModeLines(localPermissionStatus()).forEach { line in
      if line.hasPrefix("  -> App recovery:") { CLIOutput.diagnostic(line) } else { print(line) }
    }
    CLIOutput.diagnostic(
      CLILocalized.text(
        "cli.status.access_denied",
        "If access is denied, run --headless permissions request and approve "
          + "Input Monitoring and Accessibility in System Settings."
      )
    )
  }

  private func printJSON(_ payload: ApplicationServiceStatusPayload) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
      let data = try encoder.encode(payload)
      guard let text = String(bytes: data, encoding: .utf8) else {
        CLIOutput.error(
          CLILocalized.text(
            "cli.status.json_utf8_error",
            "Could not encode status JSON as UTF-8."
          )
        )
        exit(1)
      }
      print(text)
    } catch {
      CLIOutput.error(
        CLILocalized.format(
          "cli.status.json_error",
          "Could not encode status JSON: %@",
          error.localizedDescription
        )
      )
      exit(1)
    }
  }

  private func directPayload() -> ApplicationServiceStatusPayload {
    let permissions = localPermissionStatus()
    return ApplicationServiceStatusPayload(
      inputMonitoring: permissions.inputMonitoring.rawValue,
      accessibility: permissions.accessibility.rawValue,
      connectedDevices: []
    )
  }

  private func localPermissionStatus() -> StatusPermissions {
    let snapshot =
      runSyncResult(timeout: applicationServiceCallTimeoutSeconds) {
        PermissionManager.Snapshot(
          inputMonitoring: PermissionManager.currentInputMonitoringAccessState(),
          accessibility: PermissionManager.currentAccessibilityAccessState()
        )
      } ?? PermissionManager.Snapshot(inputMonitoring: .unknown, accessibility: .unknown)
    return StatusPermissions(snapshot)
  }
}
