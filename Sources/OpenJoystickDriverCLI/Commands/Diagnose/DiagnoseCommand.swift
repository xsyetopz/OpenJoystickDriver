import ArgumentParser
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverService
import OpenJoystickDriverUSB

struct DiagnoseCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "diagnose",
    abstract: CLILocalized.text(
      "cli.diagnose.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.diagnose.discussion"
    )
  )

  /// Counts the vendor-specific USB controllers; tests replace it to avoid touching USB.
  @TaskLocal
  static var usbProbe: @Sendable () async throws -> Int = {
    try await USBControllerScanner.scanVendorSpecific(
      using: OpenJoystickDriverUSBTransportProvider()
    ).count
  }

  /// Samples the service process; tests replace it to avoid sampling for seconds.
  @TaskLocal
  static var soakSampler:
    @Sendable (Int32, Int, Int, RuntimeHealthPolicy) async throws -> RuntimeHealthSummary = {
      processID,
      seconds,
      interval,
      policy in
      try await ApplicationServiceRuntimeHealthSampler.sample(
        processID: processID,
        seconds: seconds,
        intervalMilliseconds: interval,
        policy: policy
      )
    }

  /// The Apple Game Controller audit for the support bundle; tests replace it.
  @TaskLocal
  static var gameControllerAudit: @Sendable () -> AppleGameControllerSupportAudit? = {
    AppleGameControllerSupportAuditor.auditCurrentSystem()
  }

  @OptionGroup
  var global: GlobalOptions

  @Option(
    help: ArgumentHelp(
      CLILocalized.text("cli.diagnose.bundle"),
      valueName: "path"
    )
  )
  var bundle: String?

  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.diagnose.soak"
      ),
      valueName: "seconds"
    )
  )
  var soak: Int?

  @Option(
    name: .customLong("interval-ms"),
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.diagnose.interval"
      ),
      valueName: "ms"
    )
  )
  var intervalMilliseconds = 1_000

  @Option(
    name: .customLong("rss-limit-mib"),
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.diagnose.rss_limit"
      ),
      valueName: "mib"
    )
  )
  var residentLimitMiB = 0

  @Option(
    name: .customLong("footprint-limit-mib"),
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.diagnose.footprint_limit"
      ),
      valueName: "mib"
    )
  )
  var footprintLimitMiB = 512

  func validate() throws {
    if let bundle { _ = try Self.bundleURL(bundle) }
    guard let soak else { return }
    guard ApplicationServiceRuntimeHealthSampler.secondsRange.contains(soak) else {
      throw ValidationError(
        CLILocalized.text("cli.diagnose.soak_range")
      )
    }
    guard
      ApplicationServiceRuntimeHealthSampler.intervalMillisecondsRange.contains(
        intervalMilliseconds
      )
    else {
      throw ValidationError(
        CLILocalized.text(
          "cli.diagnose.interval_range"
        )
      )
    }
    let limitRange = RuntimeHealthPolicy.limitMiBRange
    guard limitRange.contains(residentLimitMiB), limitRange.contains(footprintLimitMiB) else {
      throw ValidationError(
        CLILocalized.text(
          "cli.diagnose.limit_range"
        )
      )
    }
    let samples = ApplicationServiceRuntimeHealthSampler.sampleCount(
      seconds: soak,
      intervalMilliseconds: intervalMilliseconds
    )
    guard samples <= ApplicationServiceRuntimeHealthSampler.maximumSampleCount else {
      throw ValidationError(
        CLILocalized.format(
          "cli.diagnose.sample_limit",
          samples
        )
      )
    }
  }

  /// Resolves `path` against the working directory; an existing directory gets the default
  /// file name. The parent directory must exist.
  static func bundleURL(_ path: String) throws -> URL {
    let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    var url = URL(fileURLWithPath: path, relativeTo: current).standardizedFileURL
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    {
      url.appendPathComponent(SupportReportService.defaultFilename())
    }
    let parent = url.deletingLastPathComponent().path
    guard FileManager.default.fileExists(atPath: parent, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw ValidationError(
        CLILocalized.format(
          "cli.diagnose.bundle_parent",
          parent
        )
      )
    }
    return url
  }

  func run() async throws {
    try await global.run {
      let snapshot = await DiagnoseServiceSnapshot.fetch()
      let soakOptions = soak.map {
        DiagnoseSoak(
          seconds: $0,
          intervalMilliseconds: intervalMilliseconds,
          residentLimitMiB: residentLimitMiB,
          footprintLimitMiB: footprintLimitMiB
        )
      }
      let checks = await DiagnoseChecks.run(
        snapshot: snapshot,
        extensionStatus: StatusCommand.extensionProbe(),
        soak: soakOptions
      )

      var bundleURL: URL?
      var bundleError: (any Error)?
      if let bundle {
        do {
          let url = try Self.bundleURL(bundle)
          CLIOutput.stderr(
            CLILocalized.text("cli.diagnose.bundle_progress")
          )
          try Self.writeBundle(to: url, snapshot: snapshot)
          bundleURL = url
        } catch { bundleError = error }
      }

      let report = DiagnoseReport(checks: checks, bundle: bundleURL?.path)
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(report)
      case .plain: CLIOutput.plain(report.plainRows)
      case .human: Self.printTable(report)
      }
      if let bundleURL {
        CLIOutput.success(
          CLILocalized.format(
            "cli.diagnose.bundle_written",
            bundleURL.path
          )
        )
      }
      if let bundleError {
        throw CLIFailure(
          .fileAccessFailed,
          CLILocalized.format(
            "cli.diagnose.bundle_failed",
            bundleError.localizedDescription
          )
        )
      }
      if report.failureCount > 0 {
        throw CLIFailure(
          .diagnoseFailed,
          CLILocalized.format(
            "cli.diagnose.failed",
            report.failureCount
          )
        )
      }
    }
  }

  private static func printTable(_ report: DiagnoseReport) {
    let idWidth = report.checks.map(\.id.count).max() ?? 0
    for check in report.checks {
      let id = check.id.padding(toLength: idWidth, withPad: " ", startingAt: 0)
      let status = check.status.rawValue.uppercased().padding(
        toLength: 4,
        withPad: " ",
        startingAt: 0
      )
      CLIOutput.stdout("\(status)  \(id)  \(check.detail)")
    }
  }

  private static func writeBundle(to url: URL, snapshot: DiagnoseServiceSnapshot) throws {
    let processIdentifier = ServiceConnection.processIdentifier()
    let report = SupportReportService.make(
      status: snapshot.status,
      virtualDiagnostics: snapshot.virtualDiagnostics,
      inputMonitoring: PermissionManager.AccessState(
        status: snapshot.status?.inputMonitoring ?? "unknown"
      ),
      applicationServiceHealth: ApplicationServiceManager.ApplicationServiceHealth(
        installed: ApplicationServiceManager.isInstalled,
        activeCount: processIdentifier == nil ? 0 : 1,
        state: processIdentifier == nil ? "not running" : "running",
        pid: processIdentifier.map(Int.init)
      ),
      applicationServiceInstalled: ApplicationServiceManager.isInstalled,
      applicationServiceConnected: snapshot.status != nil,
      buildIdentity: ApplicationVersion.buildIdentity,
      appleGameControllerAudit: gameControllerAudit()
    )
    try SupportReportService.write(report, to: url)
  }
}
