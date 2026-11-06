import Foundation
import OpenJoystickDriverKit

/// Assembles and writes support exports off the main actor.
///
/// The work reads logs, probes the service, and writes files, so each method runs it through
/// `BlockingWork` instead of on the `@MainActor` state that awaits it.
nonisolated struct SupportExportService: Sendable {
  /// Writes the support report to `outputURL`.
  ///
  /// - Throws: the error of ``SupportReportService`` when the report cannot be written.
  func writeReport(
    status: ApplicationServiceStatusPayload?,
    virtualDiagnostics: ApplicationServiceVirtualDeviceDiagnosticsPayload?,
    frameTimings: [ControllerFrameTimings],
    to outputURL: URL
  ) async throws {
    try await BlockingWork.run(label: "com.openjoystickdriver.support.report") {
      let report = SupportReportService.make(
        status: status,
        virtualDiagnostics: virtualDiagnostics,
        inputRead: status?.inputRead ?? .unknown,
        applicationServiceHealth: ApplicationServiceManager.health(),
        applicationServiceInstalled: ApplicationServiceManager.isInstalled,
        applicationServiceConnected: status != nil,
        buildIdentity: ApplicationVersion.buildIdentity,
        systemGamepadAudit: SystemGamepadSupportAuditor.auditCurrentSystem(),
        frameTimings: frameTimings
      )
      try SupportReportService.write(report, to: outputURL)
    }
  }

  /// Writes the end of the service logs as `ojd log export` does: `lines` lines of each log, with
  /// the home folder shown as `~`.
  func writeLogs(to outputURL: URL, lines: Int) async throws {
    try await BlockingWork.run(label: "com.openjoystickdriver.support.logs") {
      let snapshots = try ApplicationServiceLogStream.allCases.map {
        try ApplicationServiceLogService.tail(stream: $0, maximumLines: lines)
      }
      let text = ApplicationServiceLogService.exportText(
        snapshots,
        home: MacOSDataDirectory().url(for: .home).path
      )
      try Data(text.utf8).write(to: outputURL, options: .atomic)
    }
  }
}
