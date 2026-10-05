import Foundation
import OpenJoystickDriverKit

#if canImport(AppKit)
  import AppKit
#endif

/// Owns the support diagnostics, report, and log exports shown in Debug and the application menu.
@MainActor
final class SupportReportModel: ObservableObject {
  let gateway: any ApplicationServiceGateway

  @Published
  var supportDiagnosticsState: RuntimeSupportDiagnosticsState = .idle
  @Published
  var supportReportState: RuntimeSupportReportState = .idle
  @Published
  var supportLogsState: RuntimeSupportLogsState = .idle

  private var supportDiagnosticsGeneration = 0
  private var supportReportGeneration = 0
  private var supportLogsGeneration = 0

  init(gateway: any ApplicationServiceGateway) { self.gateway = gateway }

  func loadSupportDiagnostics() async {
    supportDiagnosticsGeneration &+= 1
    let generation = supportDiagnosticsGeneration
    supportDiagnosticsState = .loading
    do {
      let diagnostics = try await gateway.virtualDeviceDiagnostics()
      guard generation == supportDiagnosticsGeneration else { return }
      supportDiagnosticsState = .available(SupportDiagnosticsPresentation(payload: diagnostics))
    } catch {
      guard generation == supportDiagnosticsGeneration else { return }
      let message = RuntimePresentation.userFacingError(error)
      supportDiagnosticsState =
        RuntimePresentation.isUnavailable(error) ? .unavailable(message) : .error(message)
    }
  }

  func saveSupportReport(to outputURL: URL) async {
    supportReportGeneration &+= 1
    let reportGeneration = supportReportGeneration
    supportDiagnosticsGeneration &+= 1
    let diagnosticsGeneration = supportDiagnosticsGeneration
    supportDiagnosticsState = .loading
    supportReportState = .saving

    let status: ApplicationServiceStatusPayload?
    do { status = try await gateway.status() } catch { status = nil }

    let virtualDiagnostics: ApplicationServiceVirtualDeviceDiagnosticsPayload?
    do { virtualDiagnostics = try await gateway.virtualDeviceDiagnostics() } catch {
      virtualDiagnostics = nil
    }

    // A separate Collect action may supersede the diagnostics display while this report is
    // being assembled. The report remains an independent user operation and must still reach a
    // terminal saved/error state; only avoid replacing newer diagnostics on screen.
    if diagnosticsGeneration == supportDiagnosticsGeneration {
      if let virtualDiagnostics {
        supportDiagnosticsState = .available(
          SupportDiagnosticsPresentation(payload: virtualDiagnostics)
        )
      } else {
        supportDiagnosticsState = .unavailable(
          OJDLocalized.string(
            "debug.serviceUnavailable"
          )
        )
      }
    }

    do {
      try await SupportExportService().writeReport(
        status: status,
        virtualDiagnostics: virtualDiagnostics,
        to: outputURL
      )
      if reportGeneration == supportReportGeneration { supportReportState = .saved }
    } catch {
      if reportGeneration == supportReportGeneration {
        // Keep filesystem details out of the ordinary Debug pane.  The selected destination is
        // already visible in the save panel and the user can choose a new path on retry.
        supportReportState = .error(
          OJDLocalized.string(
            "error.supportReportSave"
          )
        )
      }
    }
  }

  #if canImport(AppKit)
    func copySupportReport() async -> Bool {
      let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        "OpenJoystickDriver-support-\(UUID().uuidString).json"
      )
      await saveSupportReport(to: outputURL)
      defer { try? FileManager.default.removeItem(at: outputURL) }
      guard let data = try? Data(contentsOf: outputURL),
        let report = String(data: data, encoding: .utf8)
      else { return false }
      NSPasteboard.general.clearContents()
      return NSPasteboard.general.setString(report, forType: .string)
    }
  #endif

  var defaultSupportReportFilename: String { SupportReportService.defaultFilename() }

  var defaultSupportLogsFilename: String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return "OpenJoystickDriver-logs-\(formatter.string(from: Date())).txt"
  }

  func saveSupportLogs(to outputURL: URL) async {
    supportLogsGeneration &+= 1
    let generation = supportLogsGeneration
    supportLogsState = .saving
    do {
      try await SupportExportService().writeLogs(to: outputURL)
      guard generation == supportLogsGeneration else { return }
      supportLogsState = .saved
    } catch {
      guard generation == supportLogsGeneration else { return }
      supportLogsState = .error(
        OJDLocalized.string(
          "error.logsSave"
        )
      )
    }
  }
}
