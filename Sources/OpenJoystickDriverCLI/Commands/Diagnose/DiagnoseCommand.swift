import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd diagnose` command: runs every check and reports what is wrong.
struct DiagnoseCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "diagnose",
    abstract: CLILocalized.text(
      "cli.diagnose.group.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.diagnose.group.discussion"
    )
  )

  /// Counts the vendor-specific USB controllers; tests replace it to avoid touching USB.
  @TaskLocal
  static var usbProbe: @Sendable () async throws -> Int = {
    try await PlatformHosts.current.countVendorSpecificUSBControllers()
  }

  /// Reads the input reports the system dropped for the service; tests replace it.
  @TaskLocal
  static var hidDropProbe: @Sendable (Int32) -> [HIDInputDropObservation] = {
    PlatformHosts.current.droppedHIDInputReports(processID: $0)
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

  /// Waits while the user moves the sticks for `--frames`; tests replace it to avoid sleeping.
  @TaskLocal
  static var frameWindowWait: @Sendable (Int) async throws -> Void = { seconds in
    try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
  }

  /// The system gamepad audit for the support bundle; tests replace it.
  @TaskLocal
  static var gameControllerAudit: @Sendable () -> SystemGamepadSupportAudit? = {
    SystemGamepadSupportAuditor.auditCurrentSystem()
  }

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// `--output`: also write a support report to this path.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text("cli.diagnose.group.output"),
      valueName: "path"
    )
  )
  var output: String?

  /// `--soak`: sample the service's memory, file descriptors and CPU for this many seconds, which
  /// runs the `runtime-health` check.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.diagnose.group.soak"
      ),
      valueName: "seconds"
    )
  )
  var soak: Int?

  /// `--interval-ms`: the milliseconds between soak samples.
  @Option(
    name: .customLong("interval-ms"),
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.diagnose.group.interval"
      ),
      valueName: "ms"
    )
  )
  var intervalMilliseconds = 1_000

  /// `--rss-limit-mib`: the resident memory in MiB that fails the soak; 0 sets no limit.
  @Option(
    name: .customLong("rss-limit-mib"),
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.diagnose.group.rssLimit"
      ),
      valueName: "mib"
    )
  )
  var residentLimitMiB = 0

  /// `--footprint-limit-mib`: the memory footprint in MiB that fails the soak.
  @Option(
    name: .customLong("footprint-limit-mib"),
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.diagnose.group.footprintLimit"
      ),
      valueName: "mib"
    )
  )
  var footprintLimitMiB = 512

  /// `--frames`: summarize only the frames read in the last this many seconds.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text("cli.diagnose.group.frames"),
      valueName: "seconds"
    )
  )
  var frames: Int?

  /// Checks the output path, the frame window and the soak seconds.
  ///
  /// - Throws: ``ValidationError`` when a value is outside its range.
  func validate() throws {
    if let output { _ = try Self.outputURL(output) }
    if let frames, !FrameTimingRecorder.windowSecondsRange.contains(frames) {
      throw ValidationError(CLILocalized.text("cli.diagnose.group.framesRange"))
    }
    guard let soak else { return }
    guard ApplicationServiceRuntimeHealthSampler.secondsRange.contains(soak) else {
      throw ValidationError(
        CLILocalized.text("cli.diagnose.group.soakRange")
      )
    }
    guard
      ApplicationServiceRuntimeHealthSampler.intervalMillisecondsRange.contains(
        intervalMilliseconds
      )
    else {
      throw ValidationError(
        CLILocalized.text(
          "cli.diagnose.group.intervalRange"
        )
      )
    }
    let limitRange = RuntimeHealthPolicy.limitMiBRange
    guard limitRange.contains(residentLimitMiB), limitRange.contains(footprintLimitMiB) else {
      throw ValidationError(
        CLILocalized.text(
          "cli.diagnose.group.limitRange"
        )
      )
    }
    let samples = ApplicationServiceRuntimeHealthSampler.sampleCount(
      seconds: soak,
      intervalMilliseconds: intervalMilliseconds
    )
    guard samples <= ApplicationServiceRuntimeHealthSampler.maximumSampleCount else {
      throw ValidationError(
        CLILocalized.plural(
          "cli.diagnose.group.sampleLimit",
          samples
        )
      )
    }
  }

  /// Resolves `path` against the working directory; an existing directory gets the default file
  /// name.
  ///
  /// The parent directory must exist.
  ///
  /// - Throws: `ValidationError` when the parent directory does not exist.
  static func outputURL(_ path: String) throws -> URL {
    let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    var url = URL(fileURLWithPath: path, relativeTo: current).standardizedFileURL
    var isDirectory: ObjCBool = false
    if unsafe FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    {
      url.appendPathComponent(SupportReportService.defaultFilename())
    }
    let parent = url.deletingLastPathComponent().path
    guard unsafe FileManager.default.fileExists(atPath: parent, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw ValidationError(
        CLILocalized.format(
          "cli.diagnose.group.outputParent",
          parent
        )
      )
    }
    return url
  }

  /// Runs the command.
  func run() async throws {
    try await global.run {
      if let frames {
        CLIOutput.stderr(
          CLILocalized.format(
            "cli.diagnose.group.framesProgress",
            Double(frames).durationText
          )
        )
        try await Self.frameWindowWait(frames)
      }
      let snapshot = await DiagnoseServiceSnapshot.fetch(frameSeconds: frames)
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

      var outputURL: URL?
      var outputError: (any Error)?
      if let output {
        do {
          let url = try Self.outputURL(output)
          CLIOutput.stderr(
            CLILocalized.text("cli.diagnose.group.outputProgress")
          )
          try Self.writeBundle(to: url, snapshot: snapshot)
          outputURL = url
        } catch { outputError = error }
      }

      let report = DiagnoseReport(
        checks: checks,
        timings: snapshot.frameTimings?.controllers ?? [],
        output: outputURL?.path
      )
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(report)
      case .plain: CLIOutput.plain(report.plainRows)
      case .human: Self.printTable(report, frameSeconds: frames)
      }
      if let outputURL {
        CLIOutput.success(
          CLILocalized.format(
            "cli.diagnose.group.outputWritten",
            outputURL.path
          )
        )
      }
      if let outputError {
        throw CLIFailure(
          .fileAccessFailed,
          CLILocalized.format(
            "cli.diagnose.group.outputFailed",
            outputError.localizedDescription
          )
        )
      }
      if report.failureCount > 0 {
        throw CLIFailure(
          .diagnoseFailed,
          CLILocalized.format(
            "cli.diagnose.group.failed",
            report.failureCount
          )
        )
      }
    }
  }

  /// Prints the check table and the frame timing blocks for people.
  private static func printTable(_ report: DiagnoseReport, frameSeconds: Int?) {
    let idWidth = report.checks.map(\.id.count).max() ?? 0
    for check in report.checks {
      let id = check.id.padding(toLength: idWidth, withPad: " ", startingAt: 0)
      let status = CommandLineName.kebab(check.status.rawValue).uppercased().padding(
        toLength: 4,
        withPad: " ",
        startingAt: 0
      )
      CLIOutput.stdout("\(status)  \(id)  \(check.detail)")
    }
    if let frameSeconds, !report.timings.isEmpty {
      CLIOutput.stdout(
        CLILocalized.format(
          "cli.diagnose.group.timingsWindow",
          Double(frameSeconds).durationText
        )
      )
    }
    for controller in report.timings {
      for line in DiagnoseReport.summaryLines(of: controller) { CLIOutput.stdout(line) }
      for frame in controller.frames {
        let stages = frame.stages.map {
          "\(CommandLineName.kebab($0.stage.rawValue))=\($0.nanoseconds)"
        }
        CLIOutput.stdout(
          CLILocalized.format(
            "cli.diagnose.group.timingsFrame",
            Int64(frame.sequence),
            controller.controller,
            controller.name,
            stages.joined(separator: " ")
          )
        )
      }
    }
  }

  /// Writes the support report bundle to `url`.
  private static func writeBundle(to url: URL, snapshot: DiagnoseServiceSnapshot) throws {
    let processIdentifier = ServiceConnection.processIdentifier()
    let report = SupportReportService.make(
      status: snapshot.status,
      virtualDiagnostics: snapshot.virtualDiagnostics,
      inputRead: snapshot.status?.inputRead ?? .unknown,
      applicationServiceHealth: ApplicationServiceManager.ApplicationServiceHealth(
        installed: ApplicationServiceManager.isInstalled,
        activeCount: processIdentifier == nil ? 0 : 1,
        state: processIdentifier == nil ? "not running" : "running",
        pid: processIdentifier.map(Int.init)
      ),
      applicationServiceInstalled: ApplicationServiceManager.isInstalled,
      applicationServiceConnected: snapshot.status != nil,
      buildIdentity: ApplicationVersion.buildIdentity,
      systemGamepadAudit: gameControllerAudit(),
      frameTimings: snapshot.frameTimings?.controllers ?? []
    )
    try SupportReportService.write(report, to: url)
  }
}
