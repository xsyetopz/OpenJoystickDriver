import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverService

/// What the service reported, or why it could not.
struct DiagnoseServiceSnapshot: Sendable {
  enum Availability: Sendable, Equatable {
    case running
    case stopped
    case failed(String)
  }

  let availability: Availability
  let status: ApplicationServiceStatusPayload?
  let virtualDiagnostics: ApplicationServiceVirtualDeviceDiagnosticsPayload?

  /// Asks the service once; a stopped or failing service never throws.
  static func fetch() async -> Self {
    do {
      let (status, diagnostics) = try await ServiceConnection.request { client in
        let status = try await client.getStatus()
        return (status, try? await client.getVirtualDeviceDiagnostics())
      }
      return Self(availability: .running, status: status, virtualDiagnostics: diagnostics)
    } catch let failure as CLIFailure where failure.code == .serviceUnavailable {
      return Self(availability: .stopped, status: nil, virtualDiagnostics: nil)
    } catch {
      let message = (error as? CLIFailure)?.message ?? error.localizedDescription
      return Self(availability: .failed(message), status: nil, virtualDiagnostics: nil)
    }
  }
}

/// The soak options of `ojd diagnose --soak`.
struct DiagnoseSoak: Sendable, Equatable {
  let seconds: Int
  let intervalMilliseconds: Int
  let residentLimitMiB: Int
  let footprintLimitMiB: Int
}

enum DiagnoseChecks {
  /// Every check in report order.
  static func run(
    snapshot: DiagnoseServiceSnapshot,
    extensionStatus: ExtensionStatus,
    soak: DiagnoseSoak?
  ) async -> [DiagnoseCheck] {
    var checks = extensionChecks(extensionStatus)
    checks.append(serviceCheck(snapshot))
    checks.append(contentsOf: permissionChecks(snapshot))
    checks.append(virtualDeviceCheck(snapshot))
    checks.append(recordCheck(RecordStore.load()))
    checks.append(await usbCheck())
    checks.append(await soakCheck(snapshot: snapshot, soak: soak))
    return checks
  }

  private static func skipped(_ id: String, _ snapshot: DiagnoseServiceSnapshot) -> DiagnoseCheck {
    let reason =
      snapshot.availability == .stopped
      ? CLILocalized.text("cli.diagnose.skip.service_stopped")
      : CLILocalized.text("cli.diagnose.skip.service_failed")
    return DiagnoseCheck(id, .skip, reason)
  }

  static func extensionChecks(_ status: ExtensionStatus) -> [DiagnoseCheck] {
    let summary = ExtensionStatusReport(status)
    let bundle: DiagnoseCheck
    switch summary.bundle {
    case .present:
      bundle = DiagnoseCheck(
        "extension-bundle",
        .pass,
        CLILocalized.text("cli.diagnose.extension.bundle_present")
      )
    case .missing:
      bundle = DiagnoseCheck(
        "extension-bundle",
        .fail,
        CLILocalized.text(
          "cli.diagnose.extension.bundle_missing"
        )
      )
    case .invalid:
      bundle = DiagnoseCheck(
        "extension-bundle",
        .fail,
        CLILocalized.format(
          "cli.diagnose.extension.bundle_invalid",
          summary.detail ?? ""
        )
      )
    }
    let registration: DiagnoseCheck
    switch summary.registration {
    case .active:
      registration = DiagnoseCheck(
        "extension-registration",
        .pass,
        CLILocalized.text("cli.diagnose.extension.active")
      )
    case .inactive:
      registration = DiagnoseCheck(
        "extension-registration",
        .warn,
        CLILocalized.text(
          "cli.diagnose.extension.inactive"
        )
      )
    case .absent:
      registration = DiagnoseCheck(
        "extension-registration",
        .warn,
        CLILocalized.text(
          "cli.diagnose.extension.absent"
        )
      )
    case .unavailable:
      registration = DiagnoseCheck(
        "extension-registration",
        .warn,
        CLILocalized.format(
          "cli.diagnose.extension.unavailable",
          summary.detail ?? ""
        )
      )
    }
    return [bundle, registration]
  }

  static func serviceCheck(_ snapshot: DiagnoseServiceSnapshot) -> DiagnoseCheck {
    switch snapshot.availability {
    case .running:
      let version = snapshot.status?.buildIdentity.semanticVersion ?? ""
      return DiagnoseCheck(
        "service",
        .pass,
        CLILocalized.format("cli.diagnose.service.running", version)
      )
    case .stopped:
      return DiagnoseCheck(
        "service",
        .warn,
        CLILocalized.text(
          "cli.diagnose.service.stopped"
        )
      )
    case .failed(let message): return DiagnoseCheck("service", .fail, message)
    }
  }

  static func permissionChecks(_ snapshot: DiagnoseServiceSnapshot) -> [DiagnoseCheck] {
    guard let status = snapshot.status else {
      return [skipped("input-monitoring", snapshot), skipped("accessibility", snapshot)]
    }
    return [
      permissionCheck("input-monitoring", status.inputMonitoring),
      permissionCheck("accessibility", status.accessibility),
    ]
  }

  private static func permissionCheck(_ id: String, _ value: String) -> DiagnoseCheck {
    switch PermissionManager.AccessState(status: value) {
    case .granted: DiagnoseCheck(id, .pass, "granted")
    case .denied:
      DiagnoseCheck(
        id,
        .fail,
        CLILocalized.text(
          "cli.diagnose.permission.denied"
        )
      )
    case .unknown:
      DiagnoseCheck(
        id,
        .warn,
        CLILocalized.text("cli.diagnose.permission.unknown")
      )
    }
  }

  static func virtualDeviceCheck(_ snapshot: DiagnoseServiceSnapshot) -> DiagnoseCheck {
    guard let status = snapshot.status else { return skipped("virtual-device", snapshot) }
    let id = "virtual-device"
    let backend = status.userSpaceVirtualDeviceStatus?.wireValue ?? "unknown"
    if case .error(let message) = status.userSpaceVirtualDeviceStatus {
      return DiagnoseCheck(
        id,
        .fail,
        CLILocalized.format("cli.diagnose.virtual.error", message)
      )
    }
    if let error = status.virtualHIDProfileOverrideError {
      return DiagnoseCheck(
        id,
        .warn,
        CLILocalized.format(
          "cli.diagnose.virtual.override",
          error
        )
      )
    }
    if status.userSpaceVirtualDeviceEnabled == false {
      return DiagnoseCheck(
        id,
        .warn,
        CLILocalized.text("cli.diagnose.virtual.disabled")
      )
    }
    return DiagnoseCheck(id, .pass, backend)
  }

  static func recordCheck(_ records: ControllerRecordSet) -> DiagnoseCheck {
    let problems = records.problems
    guard problems.isEmpty else {
      let files = problems.map { "\($0.url.lastPathComponent) (\($0.problem ?? ""))" }
      return DiagnoseCheck(
        "controller-records",
        .warn,
        CLILocalized.format(
          "cli.diagnose.records.skipped",
          files.joined(separator: "; ")
        )
      )
    }
    return DiagnoseCheck(
      "controller-records",
      .pass,
      CLILocalized.format(
        "cli.diagnose.records.applied",
        records.userFiles.count
      )
    )
  }

  private static func usbCheck() async -> DiagnoseCheck {
    do {
      let count = try await DiagnoseCommand.usbProbe()
      return DiagnoseCheck(
        "usb-access",
        .pass,
        CLILocalized.format(
          "cli.diagnose.usb.ok",
          count
        )
      )
    } catch {
      return DiagnoseCheck(
        "usb-access",
        .warn,
        CLILocalized.format(
          "cli.diagnose.usb.failed",
          error.localizedDescription
        )
      )
    }
  }

  private static func soakCheck(
    snapshot: DiagnoseServiceSnapshot,
    soak: DiagnoseSoak?
  ) async -> DiagnoseCheck {
    let id = "runtime-health"
    guard let soak else {
      return DiagnoseCheck(
        id,
        .skip,
        CLILocalized.text("cli.diagnose.soak.not_requested")
      )
    }
    guard snapshot.availability == .running, let processID = ServiceConnection.processIdentifier()
    else { return skipped(id, snapshot) }
    let mebibyte: UInt64 = 1_048_576
    let policy = RuntimeHealthPolicy(
      maximumResidentBytes: soak.residentLimitMiB == 0
        ? nil : UInt64(soak.residentLimitMiB) * mebibyte,
      maximumPhysicalFootprintBytes: soak.footprintLimitMiB == 0
        ? nil : UInt64(soak.footprintLimitMiB) * mebibyte
    )
    CLIOutput.stderr(
      CLILocalized.format(
        "cli.diagnose.soak.progress",
        Double(soak.seconds).durationText
      )
    )
    do {
      let summary = try await DiagnoseCommand.soakSampler(
        processID,
        soak.seconds,
        soak.intervalMilliseconds,
        policy
      )
      return soakCheck(summary)
    } catch { return DiagnoseCheck(id, .fail, error.localizedDescription) }
  }

  static func soakCheck(_ summary: RuntimeHealthSummary) -> DiagnoseCheck {
    let mebibyte = 1_048_576.0
    let detail = String(
      format: "%@: RSS %.1f MiB, footprint %.1f MiB, %d file descriptors, %.1f%% CPU over %.0fs",
      summary.soakVerdict.rawValue,
      Double(summary.lastResidentBytes) / mebibyte,
      Double(summary.lastPhysicalFootprintBytes) / mebibyte,
      summary.lastFileDescriptorCount,
      summary.averageCPUPercent,
      summary.durationSeconds
    )
    let status: DiagnoseStatus =
      switch summary.soakVerdict {
      case .stable: .pass
      case .insufficientData, .memoryGrowthObserved, .resourceGrowthObserved: .warn
      case .residentLimitExceeded, .physicalFootprintLimitExceeded: .fail
      }
    return DiagnoseCheck("runtime-health", status, detail)
  }
}
