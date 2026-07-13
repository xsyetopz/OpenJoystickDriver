import AppKit
import Foundation
import OpenJoystickDriverKit

@MainActor extension AppModel {
  func saveSupportReport() async {
    creatingSupportReport = true
    defer { creatingSupportReport = false }

    await syncFromApplicationServiceNow()
    let appleAudit = await Task.detached {
      AppleGameControllerSupportAuditor.auditCurrentSystem()
    }.value
    let report = SupportReportService.make(
      status: latestStatusPayload,
      virtualDiagnostics: virtualDeviceDiagnostics,
      inputMonitoring: inputMonitoringState,
      applicationServiceHealth: serviceHealth,
      applicationServiceInstalled: serviceInstalled,
      applicationServiceConnected: serviceConnected,
      appVersion: appVersion,
      appleGameControllerAudit: appleAudit
    )

    let panel = NSSavePanel()
    panel.title = L10n.string("supportReport.cardTitle")
    panel.message = L10n.string("supportReport.description")
    panel.nameFieldStringValue = SupportReportService.defaultFilename()
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    guard panel.runModal() == .OK, let outputURL = panel.url else { return }

    do {
      try SupportReportService.write(report, to: outputURL, overwrite: true)
      NSWorkspace.shared.activateFileViewerSelecting([outputURL])
    } catch {
      serviceError = error.localizedDescription
    }
  }
}
