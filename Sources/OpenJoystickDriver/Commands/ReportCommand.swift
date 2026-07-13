import Foundation
import OpenJoystickDriverKit

struct ReportCommand {
  func run(arguments: [String]) {
    var arguments = arguments
    if arguments.first == "create" {
      arguments.removeFirst()
    } else if let first = arguments.first, ["--help", "-h", "help"].contains(first) {
      printHelp()
      return
    } else if let first = arguments.first {
      print("Unknown report command: \(first)")
      printHelp()
      exit(1)
    }

    let outputURL = parseOutputURL(arguments: arguments)
    let client = ApplicationServiceClient()
    client.connect()

    let status: ApplicationServiceStatusPayload? =
      runSyncOptionalResult(timeout: 1.0) { try? await client.getStatus() }
    let virtualDiagnostics: ApplicationServiceVirtualDeviceDiagnosticsPayload? =
      status == nil
      ? nil
      : runSyncOptionalResult(timeout: 1.0) {
        try? await client.getVirtualDeviceDiagnostics()
      }
    client.disconnect()

    let permissions = PermissionManager.AccessState(
      status: status?.inputMonitoring ?? "unknown"
    )
    let health = ApplicationServiceManager.health()
    let report = SupportReportService.make(
      status: status,
      virtualDiagnostics: virtualDiagnostics,
      inputMonitoring: permissions,
      applicationServiceHealth: health,
      applicationServiceInstalled: ApplicationServiceManager.isInstalled,
      applicationServiceConnected: status != nil,
      appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        ?? "0.5.0-alpha.5",
      appleGameControllerAudit: AppleGameControllerSupportAuditor.auditCurrentSystem()
    )

    do {
      try SupportReportService.write(report, to: outputURL)
      print("Support report written to \(outputURL.path)")
      print("Review it before sharing; device product names are included.")
    } catch {
      print("ERROR: \(error.localizedDescription)")
      exit(1)
    }
  }

  private func parseOutputURL(arguments: [String]) -> URL {
    if arguments.isEmpty {
      return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(SupportReportService.defaultFilename())
    }
    guard arguments.count == 2, arguments[0] == "--output" else {
      printHelp()
      exit(1)
    }
    let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    return URL(fileURLWithPath: arguments[1], relativeTo: currentDirectory).standardizedFileURL
  }

  private func printHelp() {
    print(
      """
      Usage: OpenJoystickDriver --headless report create [--output <path>]

      Creates a JSON support report for controller issues. The report excludes
      raw serial values, filesystem paths, packet payloads, HID location IDs,
      and free-form DriverKit discovery text. Review it before sharing because
      device product names are included.
      """
    )
  }
}
