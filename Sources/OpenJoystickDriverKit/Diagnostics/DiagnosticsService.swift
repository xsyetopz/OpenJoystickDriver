import Foundation

/// The outcome of one `ojd diagnose` check.
///
/// The raw values are stable identifiers.
public enum DiagnoseStatus: String, Encodable, Equatable, Sendable {
  /// The check passed.
  case pass = "Pass"
  /// The check found something to review.
  case warn = "Warn"
  /// The check found a failure.
  case fail = "Fail"
  /// The check did not run; `detail` says why.
  case skip = "Skip"
}

/// One `ojd diagnose` check: a stable kebab-case `id`, its `status`, and a one-line `detail`.
public struct DiagnoseCheck: Encodable, Equatable, Sendable {
  /// The stable kebab-case ID of the check.
  public let id: String
  /// The outcome of the check.
  public let status: DiagnoseStatus
  /// The one-line explanation of the outcome.
  public let detail: String

  /// Creates a check from its `id`, `status` and `detail`.
  public init(_ id: String, _ status: DiagnoseStatus, _ detail: String) {
    self.id = id
    self.status = status
    self.detail = detail
  }
}

/// What the service reported, or why it could not.
public struct DiagnoseServiceSnapshot: Sendable {
  /// Whether the service answered.
  public enum Availability: Sendable, Equatable {
    /// The service answered.
    case running
    /// The service is not running.
    case stopped
    /// The service failed to answer the status request; the value is the message to show.
    case failed(String)
  }

  /// Whether the service answered.
  public let availability: Availability
  /// The service status; nil unless the service is running.
  public let status: ApplicationServiceStatusPayload?
  /// The diagnostics of the virtual devices; nil when the service did not answer that request.
  public let virtualDiagnostics: ApplicationServiceVirtualDeviceDiagnosticsPayload?
  /// The frame timings; nil when the service did not answer that request.
  public let frameTimings: ApplicationServiceFrameTimingsPayload?
  /// The record of why the service's request listener stopped; only read while the service is
  /// stopped.
  public let listenerFailure: ServiceListenerFailure.Reading

  /// Creates a snapshot from its values.
  public init(
    availability: Availability,
    status: ApplicationServiceStatusPayload?,
    virtualDiagnostics: ApplicationServiceVirtualDeviceDiagnosticsPayload?,
    frameTimings: ApplicationServiceFrameTimingsPayload?,
    listenerFailure: ServiceListenerFailure.Reading
  ) {
    self.availability = availability
    self.status = status
    self.virtualDiagnostics = virtualDiagnostics
    self.frameTimings = frameTimings
    self.listenerFailure = listenerFailure
  }
}

extension DiagnoseServiceSnapshot {
  /// Asks the service once; a stopped or failing service never throws.
  ///
  /// `classify` turns the error
  /// of a failed status request into the availability; ``availability(after:)`` is the rule for
  /// the Kit client errors. A stopped service gets `listenerFailure`, the record of why its
  /// request listener stopped.
  @preconcurrency
  public static func gather(
    status: @Sendable () async throws -> ApplicationServiceStatusPayload,
    virtualDiagnostics:
      @Sendable () async throws -> ApplicationServiceVirtualDeviceDiagnosticsPayload,
    frameTimings: @Sendable () async throws -> ApplicationServiceFrameTimingsPayload,
    classify: @Sendable (any Error) -> Availability = { availability(after: $0) },
    listenerFailure: @Sendable () -> ServiceListenerFailure.Reading
  ) async -> Self {
    do {
      let payload = try await status()
      return Self(
        availability: .running,
        status: payload,
        virtualDiagnostics: try? await virtualDiagnostics(),
        frameTimings: try? await frameTimings(),
        listenerFailure: .absent
      )
    } catch {
      let availability = classify(error)
      return Self(
        availability: availability,
        status: nil,
        virtualDiagnostics: nil,
        frameTimings: nil,
        listenerFailure: availability == .stopped ? listenerFailure() : .absent
      )
    }
  }

  /// An unreachable service is stopped; any other error leaves it failed, with the message that
  /// the command-line tool gives for a failed request.
  public static func availability(after error: any Error) -> Availability {
    if case ApplicationServiceClientError.notConnected = error { return .stopped }
    let detail = error.localizedDescription
    return .failed(
      Localization().formatted(
        "cli.shared.error.serviceRequestFailed",
        arguments: [detail.hasSuffix(".") ? String(detail.dropLast()) : detail]
      )
    )
  }
}

/// The checks of `ojd diagnose`, built from facts that the caller gathered.
public enum DiagnosticsService {
  /// The catalog that words the checks.
  private static let localization = Localization()

  /// Every check of `ojd diagnose` except runtime health, in report order, from facts that the
  /// caller gathered.
  package static func checks(
    snapshot: DiagnoseServiceSnapshot,
    extensionStatus: ExtensionStatus,
    records: ControllerRecordSet,
    virtualDevices: [VirtualPersonaFile],
    usb: Result<Int, any Error>
  ) -> [DiagnoseCheck] {
    var checks = extensionChecks(extensionStatus)
    checks.append(serviceCheck(snapshot))
    checks.append(contentsOf: permissionChecks(snapshot))
    checks.append(virtualDeviceCheck(snapshot))
    checks.append(recordCheck(records))
    checks.append(configFilesCheck(defaults: records.defaults, virtualDevices: virtualDevices))
    checks.append(usbCheck(usb))
    return checks
  }

  /// Check `id` skipped because the service is stopped or failed.
  public static func skipped(_ id: String, _ snapshot: DiagnoseServiceSnapshot) -> DiagnoseCheck {
    let reason =
      snapshot.availability == .stopped
      ? localization.string("cli.diagnose.group.skipServiceStopped")
      : localization.string("cli.diagnose.group.skipServiceFailed")
    return DiagnoseCheck(id, .skip, reason)
  }

  /// The two checks of the DriverKit extension: `transport-extension-bundle` and
  /// `transport-extension-registration`.
  package static func extensionChecks(_ status: ExtensionStatus) -> [DiagnoseCheck] {
    let bundle: DiagnoseCheck
    switch status.bundle {
    case .present:
      bundle = DiagnoseCheck(
        "transport-extension-bundle",
        .pass,
        localization.string("cli.diagnose.group.transportExtensionBundlePresent")
      )
    case .missing:
      bundle = DiagnoseCheck(
        "transport-extension-bundle",
        .fail,
        localization.string("cli.diagnose.group.transportExtensionBundleMissing")
      )
    case .invalid:
      bundle = DiagnoseCheck(
        "transport-extension-bundle",
        .fail,
        localization.formatted(
          "cli.diagnose.group.transportExtensionBundleInvalid",
          arguments: [status.detail ?? ""]
        )
      )
    }
    let registration: DiagnoseCheck
    switch status.registration {
    case .active:
      registration = DiagnoseCheck(
        "transport-extension-registration",
        .pass,
        localization.string("platform.macos.cli.diagnose.group.transportExtensionActive")
      )
    case .inactive:
      registration = DiagnoseCheck(
        "transport-extension-registration",
        .warn,
        localization.string("cli.diagnose.group.transportExtensionInactive")
      )
    case .absent:
      registration = DiagnoseCheck(
        "transport-extension-registration",
        .warn,
        localization.string("platform.macos.cli.diagnose.group.transportExtensionAbsent")
      )
    case .unavailable:
      registration = DiagnoseCheck(
        "transport-extension-registration",
        .warn,
        localization.formatted(
          "platform.macos.cli.diagnose.group.transportExtensionUnavailable",
          arguments: [status.detail ?? ""]
        )
      )
    }
    return [bundle, registration]
  }

  /// The `service` check.
  ///
  /// It passes for a running service, warns for a stopped one that left no failure record or an
  /// earlier one, and fails for a failed one, for a listener failure and for an unreadable failure
  /// record.
  public static func serviceCheck(_ snapshot: DiagnoseServiceSnapshot) -> DiagnoseCheck {
    switch snapshot.availability {
    case .running:
      let version = snapshot.status?.buildIdentity.semanticVersion ?? ""
      return DiagnoseCheck(
        "service",
        .pass,
        localization.formatted("cli.diagnose.group.serviceRunning", arguments: [version])
      )
    case .stopped:
      switch snapshot.listenerFailure {
      case .absent:
        return DiagnoseCheck(
          "service",
          .warn,
          localization.string("cli.diagnose.group.serviceStopped")
        )
      case .stopped(let failure):
        return DiagnoseCheck("service", .fail, failure.localizedSummary)
      case .earlier(let failure):
        return DiagnoseCheck("service", .warn, failure.localizedEarlierSummary)
      case .unreadable(let problem):
        return DiagnoseCheck("service", .fail, problem.localizedDescription)
      }
    case .failed(let message): return DiagnoseCheck("service", .fail, message)
    }
  }

  /// The `input-read` and `input-inject` checks; both are skipped when the service gave no status.
  public static func permissionChecks(_ snapshot: DiagnoseServiceSnapshot) -> [DiagnoseCheck] {
    guard let status = snapshot.status else {
      return [skipped("input-read", snapshot), skipped("input-inject", snapshot)]
    }
    return [
      permissionCheck("input-read", status.inputRead),
      permissionCheck("input-inject", status.inputInject),
    ]
  }

  /// The check `id` for the permission `value`: granted passes, unknown warns and denied fails.
  private static func permissionCheck(
    _ id: String,
    _ value: PermissionManager.AccessState
  )
    -> DiagnoseCheck
  {
    switch value {
    case .granted: DiagnoseCheck(id, .pass, "granted")
    case .denied:
      DiagnoseCheck(id, .fail, localization.string("cli.diagnose.group.permissionDenied"))
    case .unknown:
      DiagnoseCheck(id, .warn, localization.string("cli.diagnose.group.permissionUnknown"))
    }
  }

  /// The `virtual-device` check.
  ///
  /// It is skipped without a status, fails when the backend reports an error, warns for a profile
  /// override error or a disabled virtual device, and otherwise passes.
  public static func virtualDeviceCheck(_ snapshot: DiagnoseServiceSnapshot) -> DiagnoseCheck {
    guard let status = snapshot.status else { return skipped("virtual-device", snapshot) }
    let id = "virtual-device"
    let backend = status.userSpaceVirtualDeviceStatus?.wireValue ?? "unknown"
    if case .error(let message) = status.userSpaceVirtualDeviceStatus {
      return DiagnoseCheck(
        id,
        .fail,
        localization.formatted("cli.diagnose.group.virtualError", arguments: [message])
      )
    }
    if let error = status.virtualHIDProfileOverrideError {
      return DiagnoseCheck(
        id,
        .warn,
        localization.formatted("cli.diagnose.group.virtualOverride", arguments: [error])
      )
    }
    if status.userSpaceVirtualDeviceEnabled == false {
      return DiagnoseCheck(id, .warn, localization.string("cli.diagnose.group.virtualDisabled"))
    }
    return DiagnoseCheck(id, .pass, backend)
  }

  /// The `controller-records` check; it warns and names each controller record file that OJD
  /// skipped.
  public static func recordCheck(_ records: ControllerRecordSet) -> DiagnoseCheck {
    let problems = records.problems
    guard problems.isEmpty else {
      let files = problems.map { "\($0.url.lastPathComponent) (\($0.problem ?? ""))" }
      return DiagnoseCheck(
        "controller-records",
        .warn,
        localization.formatted(
          "cli.diagnose.group.recordsSkipped",
          arguments: [files.joined(separator: "; ")]
        )
      )
    }
    return DiagnoseCheck(
      "controller-records",
      .pass,
      localization.formatted(
        "cli.diagnose.group.recordsApplied",
        arguments: [records.userFiles.count]
      )
    )
  }

  /// The check for `all.patch.json` and the virtual device files: it warns when OJD ignored the
  /// defaults file, skipped a virtual device file, or did not read a folder, and names each.
  public static func configFilesCheck(
    defaults: ControllerDefaults?,
    virtualDevices: [VirtualPersonaFile]
  ) -> DiagnoseCheck {
    var files: [String] = []
    if let defaults, let problem = defaults.problem {
      files.append("\(defaults.url.lastPathComponent) (\(problem))")
    }
    files += virtualDevices.compactMap { file in
      file.problem.map { "\(file.url.lastPathComponent) (\($0))" }
    }
    guard files.isEmpty else {
      return DiagnoseCheck(
        "config-files",
        .warn,
        localization.formatted(
          "cli.diagnose.group.recordsConfigProblems",
          arguments: [files.joined(separator: "; ")]
        )
      )
    }
    return DiagnoseCheck(
      "config-files",
      .pass,
      localization.string("cli.diagnose.group.recordsConfigOk")
    )
  }

  /// The USB check from the number of vendor-specific controllers a probe found, or its error.
  public static func usbCheck(_ result: Result<Int, any Error>) -> DiagnoseCheck {
    switch result {
    case .success(let count):
      DiagnoseCheck(
        "usb-access",
        .pass,
        localization.formatted("cli.diagnose.group.usbOk", arguments: [count])
      )
    case .failure(let error):
      DiagnoseCheck(
        "usb-access",
        .warn,
        localization.formatted(
          "platform.macos.cli.diagnose.group.usbFailed",
          arguments: [error.localizedDescription]
        )
      )
    }
  }

  /// The `hid-input-drops` check: warns for each device whose input reports the system dropped
  /// before the service read them.
  package static func hidInputDropsCheck(_ observations: [HIDInputDropObservation]) -> DiagnoseCheck
  {
    let dropping = observations.filter { $0.droppedReports > 0 }
    guard !dropping.isEmpty else {
      return DiagnoseCheck(
        "hid-input-drops",
        .pass,
        localization.string("cli.diagnose.group.hidInputDropsNone")
      )
    }
    let detail = dropping.map {
      localization.formatted(
        "cli.diagnose.group.hidInputDropsFound",
        arguments: [
          $0.productName.isEmpty
            ? String(format: "%04X:%04X", $0.vendorID, $0.productID) : $0.productName,
          $0.droppedReports,
        ]
      )
    }.joined(separator: " ")
    return DiagnoseCheck("hid-input-drops", .warn, detail)
  }

  /// The `runtime-health` check from the measurements of a soak run.
  ///
  /// A stable run passes, a run with too little data or with growth warns, and a run over the
  /// resident or physical footprint limit fails.
  public static func soakCheck(_ summary: RuntimeHealthSummary) -> DiagnoseCheck {
    let mebibyte = 1_048_576.0
    let detail = localization.formatted(
      verdictKey(summary.soakVerdict),
      arguments: [
        Double(summary.lastResidentBytes) / mebibyte,
        Double(summary.lastPhysicalFootprintBytes) / mebibyte,
        summary.lastFileDescriptorCount,
        summary.averageCPUPercent,
        summary.durationSeconds,
      ]
    )
    let status: DiagnoseStatus =
      switch summary.soakVerdict {
      case .stable: .pass
      case .insufficientData, .memoryGrowthObserved, .resourceGrowthObserved: .warn
      case .residentLimitExceeded, .physicalFootprintLimitExceeded: .fail
      }
    return DiagnoseCheck("runtime-health", status, detail)
  }

  /// The catalog entry that words the verdict and the measurements of one soak run.
  static func verdictKey(_ verdict: RuntimeSoakVerdict) -> String {
    switch verdict {
    case .insufficientData: "cli.diagnose.group.soakVerdictInsufficientData"
    case .stable: "cli.diagnose.group.soakVerdictStable"
    case .memoryGrowthObserved: "cli.diagnose.group.soakVerdictMemoryGrowth"
    case .resourceGrowthObserved: "cli.diagnose.group.soakVerdictResourceGrowth"
    case .residentLimitExceeded: "cli.diagnose.group.soakVerdictResidentLimit"
    case .physicalFootprintLimitExceeded: "cli.diagnose.group.soakVerdictFootprintLimit"
    }
  }
}
