import Combine
import Foundation
import OpenJoystickDriverKit

#if canImport(AppKit)
  import AppKit
#endif

/// Holds the state of the virtual device diagnostics, the support report and the log export, which
/// the Activity area and the File and Help menus start.
@MainActor
final class SupportReportModel: ObservableObject {
  /// The connection to the service.
  let gateway: any ApplicationServiceGateway

  /// Whether the virtual device diagnostics are loaded.
  @Published
  var supportDiagnosticsState: RuntimeSupportDiagnosticsState = .idle
  /// Where saving the support report is.
  @Published
  var supportReportState: RuntimeSupportReportState = .idle
  /// Where saving the logs is.
  @Published
  var supportLogsState: RuntimeSupportLogsState = .idle

  /// The line count of a saved log: the CLI's export default until the Activity log's line count is
  /// changed, then that count.
  ///
  /// The Save Activity Log menu item and the Activity toolbar save the same thing.
  var logExportLines = ApplicationServiceLogService.defaultExportLines

  /// Counts the diagnostics reads, so that a read can tell whether another began.
  private var supportDiagnosticsGeneration = 0
  /// Counts the report saves, so that a save can tell whether another began.
  private var supportReportGeneration = 0
  /// Counts the log saves, so that a save can tell whether another began.
  private var supportLogsGeneration = 0

  /// Creates the model on a service gateway.
  init(gateway: any ApplicationServiceGateway) { self.gateway = gateway }

  /// Reads the virtual device diagnostics from the service.
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

  /// Collects the status, the diagnostics and the frame timings and writes the support report to
  /// `outputURL`.
  ///
  /// A service that does not answer leaves its parts empty. The result shows in
  /// ``supportReportState``.
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

    // Like `ojd diagnose --output`, an unreachable service leaves the timings empty.
    let frameTimings = (try? await gateway.frameTimings(lastSeconds: nil).controllers) ?? []

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
            "ui.debug.serviceUnavailable"
          )
        )
      }
    }

    do {
      try await SupportExportService().writeReport(
        status: status,
        virtualDiagnostics: virtualDiagnostics,
        frameTimings: frameTimings,
        to: outputURL
      )
      if reportGeneration == supportReportGeneration { supportReportState = .saved }
    } catch {
      if reportGeneration == supportReportGeneration {
        // Keep filesystem details out of the ordinary Debug pane.  The selected destination is
        // already visible in the save panel and the user can choose another path on retry.
        supportReportState = .error(
          OJDLocalized.string(
            "ui.error.supportReportSave"
          )
        )
      }
    }
  }

  #if canImport(AppKit)
    /// Writes the support report to a temporary file, copies its text to the pasteboard and returns
    /// whether that worked.
    func copySupportReport() async -> Bool {
      let outputURL = MacOSDataDirectory().fileURL(
        "OpenJoystickDriver-support-\(UUID().uuidString).json",
        in: .temporary
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

  /// The file name that Save Support Report offers.
  var defaultSupportReportFilename: String { SupportReportService.defaultFilename() }

  /// The file name that Save Activity Log offers, with the UTC date and time.
  var defaultSupportLogsFilename: String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return "OpenJoystickDriver-logs-\(formatter.string(from: Date())).txt"
  }

  /// Writes the last ``logExportLines`` lines of each service log to `outputURL`.
  ///
  /// The result shows in ``supportLogsState``.
  func saveSupportLogs(to outputURL: URL) async {
    supportLogsGeneration &+= 1
    let generation = supportLogsGeneration
    supportLogsState = .saving
    do {
      try await SupportExportService().writeLogs(
        to: outputURL,
        lines: logExportLines
      )
      guard generation == supportLogsGeneration else { return }
      supportLogsState = .saved
    } catch {
      guard generation == supportLogsGeneration else { return }
      supportLogsState = .error(
        OJDLocalized.string("ui.error.logsSave") + "\n" + error.localizedDescription
      )
    }
  }
}
