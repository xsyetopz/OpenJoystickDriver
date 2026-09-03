import Foundation
import OpenJoystickDriverKit

#if canImport(AppKit)
  import AppKit
#endif

struct SupportDiagnosticsPresentation: Sendable, Equatable {
  enum VirtualControllerOutputState: String, Sendable, Equatable {
    case available
    case unavailable
    case needsAttention
  }

  let virtualControllerOutputState: VirtualControllerOutputState
  let virtualControllerCount: Int

  init(payload: ApplicationServiceVirtualDeviceDiagnosticsPayload) {
    self.init(diagnostics: payload)
  }

  init(diagnostics: ApplicationServiceVirtualDeviceDiagnosticsPayload) {
    let status = diagnostics.userSpaceVirtualDeviceStatus.trimmingCharacters(
      in: .whitespacesAndNewlines
    ).lowercased()
    if status.hasPrefix("error:") {
      virtualControllerOutputState = .needsAttention
    } else if diagnostics.userSpaceVirtualDeviceEnabled {
      virtualControllerOutputState = .available
    } else {
      virtualControllerOutputState = .unavailable
    }
    virtualControllerCount = diagnostics.hidGamepads.count(where: \.isOJDUserSpace)
  }

  var virtualControllerOutputLabel: String {
    switch virtualControllerOutputState {
    case .available: return OJDLocalized.string("common.available", fallback: "Available")
    case .unavailable: return OJDLocalized.string("common.unavailable", fallback: "Unavailable")
    case .needsAttention:
      return OJDLocalized.string("common.needsAttention", fallback: "Needs attention")
    }
  }

  var virtualControllerOutputDetail: String {
    switch virtualControllerOutputState {
    case .available:
      return OJDLocalized.string(
        "debug.outputAvailable",
        fallback: "Controller output is available."
      )
    case .unavailable:
      return OJDLocalized.string("debug.outputOff", fallback: "Controller output is turned off.")
    case .needsAttention:
      return OJDLocalized.string(
        "debug.outputNeedsAttention",
        fallback: "Controller output needs attention."
      )
    }
  }

  var virtualControllerCountLabel: String {
    OJDLocalized.plural(
      "debug.outputDevices",
      count: virtualControllerCount,
      fallback: "%d controller output devices detected"
    )
  }
}

enum RuntimeSupportDiagnosticsState: Sendable {
  case idle
  case loading
  case available(SupportDiagnosticsPresentation)
  case unavailable(String)
  case error(String)
}

enum RuntimeSupportReportState: Sendable {
  case idle
  case saving
  case saved
  case error(String)
}

enum RuntimeSupportLogsState: Sendable {
  case idle
  case saving
  case saved
  case error(String)
}

@MainActor extension RuntimeViewModel {
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
            "debug.serviceUnavailable",
            fallback: "Service diagnostics are unavailable right now."
          )
        )
      }
    }

    let reportContext = await Task.detached(priority: nil) {
      (
        health: ApplicationServiceManager.health(),
        installed: ApplicationServiceManager.isInstalled,
        appleGameControllerAudit: AppleGameControllerSupportAuditor.auditCurrentSystem()
      )
    }.value
    let report = await Task.detached(priority: nil) {
      SupportReportService.make(
        status: status,
        virtualDiagnostics: virtualDiagnostics,
        inputMonitoring: PermissionManager.AccessState(
          status: status?.inputMonitoring ?? "unknown"
        ),
        applicationServiceHealth: reportContext.health,
        applicationServiceInstalled: reportContext.installed,
        applicationServiceConnected: status != nil,
        appVersion: ApplicationVersion.current,
        appleGameControllerAudit: reportContext.appleGameControllerAudit
      )
    }.value

    do {
      try await Task.detached(priority: nil) {
        try SupportReportService.write(report, to: outputURL)
      }.value
      if reportGeneration == supportReportGeneration { supportReportState = .saved }
    } catch {
      if reportGeneration == supportReportGeneration {
        // Keep filesystem details out of the ordinary Debug pane.  The selected destination is
        // already visible in the save panel and the user can choose a new path on retry.
        supportReportState = .error(
          OJDLocalized.string(
            "error.supportReportSave",
            fallback: "The support report couldn’t be saved. Choose another file and try again."
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
      let text = try await Task.detached(priority: nil) {
        let snapshots = try ApplicationServiceLogStream.allCases.map {
          try ApplicationServiceLogService.tail(stream: $0)
        }
        return snapshots.map { snapshot in
          var section = "== \(snapshot.stream.rawValue) ==\n"
          if snapshot.exists {
            section += snapshot.lines.joined(separator: "\n")
            if !snapshot.lines.isEmpty { section += "\n" }
            if snapshot.truncated { section += "[tail truncated]\n" }
          } else {
            section += "[no log available]\n"
          }
          return section
        }.joined(separator: "\n")
      }.value
      try await Task.detached(priority: nil) {
        try Data(text.utf8).write(to: outputURL, options: .atomic)
      }.value
      guard generation == supportLogsGeneration else { return }
      supportLogsState = .saved
    } catch {
      guard generation == supportLogsGeneration else { return }
      supportLogsState = .error(
        OJDLocalized.string(
          "error.logsSave",
          fallback: "The logs couldn’t be saved. Choose another file and try again."
        )
      )
    }
  }

}
