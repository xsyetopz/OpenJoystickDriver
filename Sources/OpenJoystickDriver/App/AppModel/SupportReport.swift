import AppKit
import Foundation
import OpenJoystickDriverKit

@MainActor extension AppModel {
  func saveSupportReport() async {
    creatingSupportReport = true
    defer { creatingSupportReport = false }

    await syncFromDaemonNow()
    if appleGameControllerAudit == nil {
      await runAppleGameControllerAudit()
    }
    let report = SupportReportService.make(
      status: latestStatusPayload,
      virtualDiagnostics: virtualDeviceDiagnostics,
      permissions: inputMonitoringPermissions,
      daemonHealth: daemonHealth,
      daemonInstalled: daemonInstalled,
      daemonConnected: daemonConnected,
      appVersion: appVersion,
      runtimeHealth: runtimeHealthSummary,
      appleGameControllerAudit: appleGameControllerAudit
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
      daemonError = error.localizedDescription
    }
  }
  func runRuntimeHealthCheck(
    seconds: Int = 60,
    intervalMilliseconds: Int = 1_000,
    residentLimitMiB: Int = 0,
    physicalFootprintLimitMiB: Int = 512
  ) async {
    stopRuntimeHealthCheck()
    runtimeHealthSummary = nil

    guard (1...86_400).contains(seconds),
      (100...60_000).contains(intervalMilliseconds),
      (0...65_536).contains(residentLimitMiB),
      (0...65_536).contains(physicalFootprintLimitMiB)
    else {
      daemonError = L10n.string("runtimeHealth.invalidConfiguration")
      return
    }
    let estimatedSamples =
      Int(ceil(Double(seconds * 1_000) / Double(intervalMilliseconds))) + 1
    guard estimatedSamples <= DaemonRuntimeHealthSampler.maximumSampleCount else {
      daemonError = L10n.string(
        "runtimeHealth.tooManySamples",
        estimatedSamples
      )
      return
    }

    await refreshDaemonHealth()
    guard let processID = daemonHealth?.pid else {
      daemonError = "OpenJoystickDriver daemon is not running."
      return
    }

    let policy = RuntimeHealthPolicy(
      maximumResidentBytes:
        residentLimitMiB == 0
        ? nil
        : UInt64(residentLimitMiB) * 1_048_576,
      maximumPhysicalFootprintBytes:
        physicalFootprintLimitMiB == 0
        ? nil
        : UInt64(physicalFootprintLimitMiB) * 1_048_576
    )
    let runID = UUID()
    let task = Task.detached {
      try await DaemonRuntimeHealthSampler.sample(
        processID: Int32(processID),
        seconds: seconds,
        intervalMilliseconds: intervalMilliseconds,
        policy: policy
      )
    }
    runtimeHealthRunID = runID
    runtimeHealthTask = task
    runtimeHealthRunning = true

    do {
      let summary = try await task.value
      guard runtimeHealthRunID == runID else { return }
      runtimeHealthSummary = summary
    } catch is CancellationError {
      return
    } catch {
      guard runtimeHealthRunID == runID else { return }
      daemonError = error.localizedDescription
    }
    if runtimeHealthRunID == runID {
      runtimeHealthTask = nil
      runtimeHealthRunID = nil
      runtimeHealthRunning = false
    }
  }

  func stopRuntimeHealthCheck() {
    runtimeHealthTask?.cancel()
    runtimeHealthTask = nil
    runtimeHealthRunID = nil
    runtimeHealthRunning = false
  }
}
