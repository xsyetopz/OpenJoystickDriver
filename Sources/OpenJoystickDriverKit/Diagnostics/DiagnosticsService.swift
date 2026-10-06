import Foundation

/// The outcome of one `ojd diagnose` check. The raw values are stable identifiers.
public enum DiagnoseStatus: String, Encodable, Equatable, Sendable {
  case pass
  case warn
  case fail
  case skip
}

/// One `ojd diagnose` check: a stable kebab-case `id`, its `status`, and a one-line `detail`.
public struct DiagnoseCheck: Encodable, Equatable, Sendable {
  public let id: String
  public let status: DiagnoseStatus
  public let detail: String

  public init(_ id: String, _ status: DiagnoseStatus, _ detail: String) {
    self.id = id
    self.status = status
    self.detail = detail
  }
}

/// What the service reported, or why it could not.
public struct DiagnoseServiceSnapshot: Sendable {
  public enum Availability: Sendable, Equatable {
    case running
    case stopped
    case failed(String)
  }

  public let availability: Availability
  public let status: ApplicationServiceStatusPayload?
  public let virtualDiagnostics: ApplicationServiceVirtualDeviceDiagnosticsPayload?

  public init(
    availability: Availability,
    status: ApplicationServiceStatusPayload?,
    virtualDiagnostics: ApplicationServiceVirtualDeviceDiagnosticsPayload?
  ) {
    self.availability = availability
    self.status = status
    self.virtualDiagnostics = virtualDiagnostics
  }
}

/// The checks of `ojd diagnose`, built from facts that the caller gathered.
public enum DiagnosticsService {
  private static let localization = Localization()

  /// Check `id` skipped because the service is stopped or failed.
  public static func skipped(_ id: String, _ snapshot: DiagnoseServiceSnapshot) -> DiagnoseCheck {
    let reason =
      snapshot.availability == .stopped
      ? localization.string("cli.diagnose.skip.service_stopped")
      : localization.string("cli.diagnose.skip.service_failed")
    return DiagnoseCheck(id, .skip, reason)
  }

  package static func extensionChecks(_ status: ExtensionStatus) -> [DiagnoseCheck] {
    let bundle: DiagnoseCheck
    switch status.bundle {
    case .present:
      bundle = DiagnoseCheck(
        "extension-bundle",
        .pass,
        localization.string("cli.diagnose.extension.bundle_present")
      )
    case .missing:
      bundle = DiagnoseCheck(
        "extension-bundle",
        .fail,
        localization.string("cli.diagnose.extension.bundle_missing")
      )
    case .invalid:
      bundle = DiagnoseCheck(
        "extension-bundle",
        .fail,
        localization.formatted(
          "cli.diagnose.extension.bundle_invalid",
          arguments: [status.detail ?? ""]
        )
      )
    }
    let registration: DiagnoseCheck
    switch status.registration {
    case .active:
      registration = DiagnoseCheck(
        "extension-registration",
        .pass,
        localization.string("cli.diagnose.extension.active")
      )
    case .inactive:
      registration = DiagnoseCheck(
        "extension-registration",
        .warn,
        localization.string("cli.diagnose.extension.inactive")
      )
    case .absent:
      registration = DiagnoseCheck(
        "extension-registration",
        .warn,
        localization.string("cli.diagnose.extension.absent")
      )
    case .unavailable:
      registration = DiagnoseCheck(
        "extension-registration",
        .warn,
        localization.formatted(
          "cli.diagnose.extension.unavailable",
          arguments: [status.detail ?? ""]
        )
      )
    }
    return [bundle, registration]
  }

  public static func serviceCheck(_ snapshot: DiagnoseServiceSnapshot) -> DiagnoseCheck {
    switch snapshot.availability {
    case .running:
      let version = snapshot.status?.buildIdentity.semanticVersion ?? ""
      return DiagnoseCheck(
        "service",
        .pass,
        localization.formatted("cli.diagnose.service.running", arguments: [version])
      )
    case .stopped:
      return DiagnoseCheck("service", .warn, localization.string("cli.diagnose.service.stopped"))
    case .failed(let message): return DiagnoseCheck("service", .fail, message)
    }
  }

  public static func permissionChecks(_ snapshot: DiagnoseServiceSnapshot) -> [DiagnoseCheck] {
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
      DiagnoseCheck(id, .fail, localization.string("cli.diagnose.permission.denied"))
    case .unknown:
      DiagnoseCheck(id, .warn, localization.string("cli.diagnose.permission.unknown"))
    }
  }

  public static func virtualDeviceCheck(_ snapshot: DiagnoseServiceSnapshot) -> DiagnoseCheck {
    guard let status = snapshot.status else { return skipped("virtual-device", snapshot) }
    let id = "virtual-device"
    let backend = status.userSpaceVirtualDeviceStatus?.wireValue ?? "unknown"
    if case .error(let message) = status.userSpaceVirtualDeviceStatus {
      return DiagnoseCheck(
        id,
        .fail,
        localization.formatted("cli.diagnose.virtual.error", arguments: [message])
      )
    }
    if let error = status.virtualHIDProfileOverrideError {
      return DiagnoseCheck(
        id,
        .warn,
        localization.formatted("cli.diagnose.virtual.override", arguments: [error])
      )
    }
    if status.userSpaceVirtualDeviceEnabled == false {
      return DiagnoseCheck(id, .warn, localization.string("cli.diagnose.virtual.disabled"))
    }
    return DiagnoseCheck(id, .pass, backend)
  }

  public static func recordCheck(_ records: ControllerRecordSet) -> DiagnoseCheck {
    let problems = records.problems
    guard problems.isEmpty else {
      let files = problems.map { "\($0.url.lastPathComponent) (\($0.problem ?? ""))" }
      return DiagnoseCheck(
        "controller-records",
        .warn,
        localization.formatted(
          "cli.diagnose.records.skipped",
          arguments: [files.joined(separator: "; ")]
        )
      )
    }
    return DiagnoseCheck(
      "controller-records",
      .pass,
      localization.formatted("cli.diagnose.records.applied", arguments: [records.userFiles.count])
    )
  }

  /// The USB check from the number of vendor-specific controllers a probe found, or its error.
  public static func usbCheck(_ result: Result<Int, any Error>) -> DiagnoseCheck {
    switch result {
    case .success(let count):
      DiagnoseCheck(
        "usb-access",
        .pass,
        localization.formatted("cli.diagnose.usb.ok", arguments: [count])
      )
    case .failure(let error):
      DiagnoseCheck(
        "usb-access",
        .warn,
        localization.formatted("cli.diagnose.usb.failed", arguments: [error.localizedDescription])
      )
    }
  }

  public static func soakCheck(_ summary: RuntimeHealthSummary) -> DiagnoseCheck {
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
