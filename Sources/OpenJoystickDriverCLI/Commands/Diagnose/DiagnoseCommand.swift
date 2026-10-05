import ArgumentParser
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverService
import OpenJoystickDriverUSB

struct DiagnoseCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "diagnose",
    abstract: CLILocalized.text(
      "cli.diagnose.abstract",
      "Run every check and report what is wrong."
    ),
    discussion: CLILocalized.text(
      "cli.diagnose.discussion",
      """
      Each check reports pass, warn, fail, or skip. Checks that need the service are skipped \
      while it is stopped. Exits 1 when any check fails. --soak adds a runtime-health check \
      that samples the service for the given time; without it that check is skipped. \
      --bundle also writes a support report; review it before sharing.
      """
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
      CLILocalized.text("cli.diagnose.bundle", "Also write a support bundle to this file."),
      valueName: "path"
    )
  )
  var bundle: String?

  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.diagnose.soak",
        "Also sample the service's memory, file descriptors, and CPU for this long (1-86400)."
      ),
      valueName: "seconds"
    )
  )
  var soak: Int?

  @Option(
    name: .customLong("interval-ms"),
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.diagnose.interval",
        "With --soak, milliseconds between samples (100-60000)."
      ),
      valueName: "ms"
    )
  )
  var intervalMilliseconds = 1_000

  @Option(
    name: .customLong("rss-limit-mib"),
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.diagnose.rss_limit",
        "With --soak, fail above this resident size in MiB; 0 disables (0-65536)."
      ),
      valueName: "mib"
    )
  )
  var residentLimitMiB = 0

  @Option(
    name: .customLong("footprint-limit-mib"),
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.diagnose.footprint_limit",
        "With --soak, fail above this physical footprint in MiB; 0 disables (0-65536)."
      ),
      valueName: "mib"
    )
  )
  var footprintLimitMiB = 512

  func validate() throws {
    if let bundle { _ = try Self.bundleURL(bundle) }
    guard let soak else { return }
    guard (1...86_400).contains(soak) else {
      throw ValidationError(
        CLILocalized.text("cli.diagnose.soak_range", "--soak must be between 1 and 86400 seconds.")
      )
    }
    guard (100...60_000).contains(intervalMilliseconds) else {
      throw ValidationError(
        CLILocalized.text(
          "cli.diagnose.interval_range",
          "--interval-ms must be between 100 and 60000."
        )
      )
    }
    guard (0...65_536).contains(residentLimitMiB), (0...65_536).contains(footprintLimitMiB) else {
      throw ValidationError(
        CLILocalized.text(
          "cli.diagnose.limit_range",
          "--rss-limit-mib and --footprint-limit-mib must be between 0 and 65536."
        )
      )
    }
    let samples = Int((Double(soak * 1_000) / Double(intervalMilliseconds)).rounded(.up)) + 1
    guard samples <= ApplicationServiceRuntimeHealthSampler.maximumSampleCount else {
      throw ValidationError(
        CLILocalized.format(
          "cli.diagnose.sample_limit",
          "--soak with this --interval-ms would take %lld samples; raise --interval-ms.",
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
          "--bundle needs an existing directory; %@ does not exist.",
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
            CLILocalized.text("cli.diagnose.bundle_progress", "Writing the support bundle...")
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
            "Support bundle written to %@. Review it before sharing; device names are included.",
            bundleURL.path
          )
        )
      }
      if let bundleError {
        throw CLIFailure(
          .fileAccessFailed,
          CLILocalized.format(
            "cli.diagnose.bundle_failed",
            "The support bundle was not written: %@. Choose another --bundle path.",
            bundleError.localizedDescription
          )
        )
      }
      if report.failureCount > 0 {
        throw CLIFailure(
          .diagnoseFailed,
          CLILocalized.format(
            "cli.diagnose.failed",
            "Failed checks: %lld. Fix them using the details above, or run "
              + "'ojd diagnose --bundle <path>' and attach the file to a bug report.",
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
