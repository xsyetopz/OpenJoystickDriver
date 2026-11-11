import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd status` command: reports the service, the DriverKit extension, the `ojd` link, the
/// input permissions, the virtual gamepad, and the connected and unbound devices.
///
/// It reads the extension, the link and the skipped records without the service.
struct StatusCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "status",
    abstract: CLILocalized.text(
      "cli.status.group.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.status.group.discussion"
    )
  )

  /// Reads the DriverKit extension state; tests replace it to avoid `systemextensionsctl`.
  @TaskLocal
  static var extensionProbe: @Sendable () -> ExtensionStatus = {
    PlatformHosts.current.extensionStatus(
      bundleURL: ServiceStartCommand.applicationBundleURL() ?? Bundle.main.bundleURL
    )
  }

  /// Reads the command-line tool link; tests point it at a folder they own.
  @TaskLocal
  static var linkProbe: @Sendable () -> CommandLineToolLinkStatus = {
    CommandLineToolLinkStatus.probe()
  }

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let payload: ApplicationServiceStatusPayload?
      do { payload = try await ServiceConnection.request { try await $0.getStatus() } } catch let
        failure as CLIFailure where failure.code == .serviceUnavailable
      { payload = nil }
      let records = RecordStore.load()
      let reading =
        payload == nil
        ? ServiceListenerFailure.read(socketPath: ServiceConnection.socketPath) : .absent
      let report = StatusReport(
        payload: payload,
        extensionStatus: Self.extensionProbe(),
        commandLineTool: Self.linkProbe(),
        skippedRecords: records.problems.map(SkippedRecord.init),
        ignoredDefaults: SkippedRecord(records.defaults),
        skippedVirtualDevices: RecordStore.virtualDeviceFiles().filter { $0.problem != nil }
          .map(SkippedRecord.init),
        listenerFailure: reading
      )
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(report)
      case .plain: CLIOutput.plain(Self.plainRows(report))
      case .human: Self.printHuman(report)
      }
      try Self.failIfListenerBroken(reading)
    }
  }

  /// Fails after the report when the stopped service left a listener failure that needs attention.
  ///
  /// A service that is unreachable because its request listener stopped fails with `E2034`, and one
  /// whose record of that cannot be used with `E2035`. A record of a service that is not running
  /// only informs.
  ///
  /// - Throws: ``CLIFailure`` with the failure code of the record, or
  ///   `damagedListenerFailureRecord`.
  static func failIfListenerBroken(_ reading: ServiceListenerFailure.Reading) throws {
    switch reading {
    case .absent, .earlier: return
    case .stopped(let failure):
      throw CLIFailure(failure.code, failure.code.localizedExplanation)
    case .unreadable(let problem):
      throw CLIFailure(.damagedListenerFailureRecord, problem.explanation)
    }
  }

  /// Returns the `--plain` rows of `report`.
  static func plainRows(_ report: StatusReport) -> [[String]] {
    var rows = [
      [
        "service", CommandLineName.kebab(report.service.state.rawValue),
        report.service.version ?? "",
      ],
      [
        "transport-extension", CommandLineName.kebab(report.transportExtension.bundle.rawValue),
        CommandLineName.kebab(report.transportExtension.registration.rawValue),
      ],
      [
        "command-line-tool", CommandLineName.kebab(report.commandLineTool.state.rawValue),
        report.commandLineTool.path,
      ],
    ]
    if let failure = report.service.listenerFailure {
      rows.append([
        "listener-failure", failure.code, String(failure.errorNumber), failure.time,
        failure.current ? "current" : "earlier",
      ])
    }
    if let problem = report.service.listenerFailureProblem {
      rows.append(["listener-failure-problem", problem])
    }
    if let permissions = report.permissions {
      rows.append([
        "permission", "input-read", CommandLineName.kebab(permissions.inputRead.rawValue),
      ])
      rows.append([
        "permission", "input-inject", CommandLineName.kebab(permissions.inputInject.rawValue),
      ])
    }
    if let virtual = report.virtualDevice {
      rows.append([
        "virtual-device", virtual.enabled.map { $0 ? "enabled" : "disabled" } ?? "unknown",
        virtual.status ?? "",
      ])
    }
    for controller in report.controllers ?? [] {
      rows.append([
        "controller", controller.id,
        deviceIdentity(vendorID: controller.vendorID, productID: controller.productID),
        controller.connection, controller.name,
      ])
      if controller.paused { rows.append(["paused", controller.id]) }
      if let mapping = controller.inputMapping {
        rows.append(["input-mapping", controller.id] + mapping.plainFields)
      }
    }
    for device in report.unboundDevices ?? [] {
      rows.append([
        "unbound", deviceIdentity(vendorID: device.vendorID, productID: device.productID),
        device.connection, device.reason.map(CommandLineName.kebab) ?? "",
      ])
      if let mapping = device.inputMapping {
        rows.append(
          ["input-mapping", deviceIdentity(vendorID: device.vendorID, productID: device.productID)]
            + mapping.plainFields
        )
      }
    }
    for device in report.passThroughDevices ?? [] {
      rows.append([
        "pass-through", deviceIdentity(vendorID: device.vendorID, productID: device.productID),
        device.connection,
      ])
    }
    for skipped in report.skippedRecords {
      rows.append(["skipped-record", skipped.file, skipped.problem])
    }
    if let ignored = report.ignoredDefaults {
      rows.append(["ignored-defaults", ignored.file, ignored.problem])
    }
    for skipped in report.skippedVirtualDevices {
      rows.append(["skipped-virtual-device", skipped.file, skipped.problem])
    }
    return rows
  }

  /// Summarizes the virtual gamepad for the text output: off, the backend's error, or the names of
  /// the controllers it publishes.
  ///
  /// The per-controller diagnostics stay in `--json`, `--plain` and `ojd diagnose`.
  static func virtualDeviceSummary(
    _ virtual: StatusReport.VirtualDevice,
    controllers: [StatusReport.Controller]
  ) -> String {
    if virtual.enabled == false { return CLILocalized.text("cli.status.group.virtualOff") }
    if case .error(let message) = virtual.status.map(VirtualOutputBackendStatus.init(wireValue:)) {
      return CLILocalized.format("cli.status.group.virtualError", message)
    }
    let names = controllers.filter { virtual.published.contains($0.id) }.map(\.name)
    return names.isEmpty
      ? CLILocalized.text("cli.status.group.virtualNonePublished")
      : CLILocalized.format("cli.status.group.virtualPublished", names.joined(separator: ", "))
  }

  /// Prints `report` as labeled rows, then the devices.
  private static func printHuman(_ report: StatusReport) {
    let transport = report.transportExtension
    var rows: [(String, String)] = [
      (
        CLILocalized.text("cli.status.group.labelService"),
        CommandLineName.kebab(report.service.state.rawValue)
          + (report.service.version.map { " (\($0))" } ?? "")
      ),
      (
        CLILocalized.text("cli.status.group.labelTransportExtension"),
        "\(CommandLineName.kebab(transport.bundle.rawValue)), "
          + CommandLineName.kebab(transport.registration.rawValue)
      ),
      (
        CLILocalized.text("cli.status.group.labelCommandLineTool"),
        "\(CommandLineName.kebab(report.commandLineTool.state.rawValue)), "
          + report.commandLineTool.path
      ),
    ]
    if let failure = report.service.listenerFailure {
      rows.append((CLILocalized.text("cli.status.group.listenerFailureLabel"), failure.message))
    }
    if let problem = report.service.listenerFailureProblem {
      rows.append((CLILocalized.text("cli.status.group.listenerFailureLabel"), problem))
    }
    if let permissions = report.permissions {
      rows.append(
        (
          CLILocalized.text("platform.macos.cli.status.group.labelInputRead"),
          CommandLineName.kebab(permissions.inputRead.rawValue)
        )
      )
      rows.append(
        (
          CLILocalized.text("platform.macos.cli.status.group.labelInputInject"),
          CommandLineName.kebab(permissions.inputInject.rawValue)
        )
      )
    }
    if let virtual = report.virtualDevice {
      rows.append(
        (
          CLILocalized.text("cli.status.group.labelVirtualDevice"),
          virtualDeviceSummary(virtual, controllers: report.controllers ?? [])
        )
      )
      if let error = virtual.overrideError {
        rows.append((CLILocalized.text("cli.status.group.labelOverrideError"), error))
      }
    }
    let width = rows.map(\.0.count).max() ?? 0
    for (label, value) in rows {
      CLIOutput.stdout(label.padding(toLength: width, withPad: " ", startingAt: 0) + "  " + value)
    }
    printDevices(report)
    if report.service.state == .stopped {
      CLIOutput.stderr(
        CLILocalized.text(
          "cli.status.group.startHint"
        )
      )
    }
  }

  /// Prints the Input mapping row under a device.
  private static func printMapping(_ mapping: InputMapping?) {
    guard let mapping else { return }
    CLIOutput.stdout(
      "    \(CLILocalized.text("cli.controller.show.labelInputMapping")): "
        + mapping.rowText(localize: CLILocalized.text)
    )
  }

  /// Prints the connected controllers and the devices that have no binding or that pass through.
  private static func printDevices(_ report: StatusReport) {
    if let controllers = report.controllers {
      CLIOutput.stdout("")
      CLIOutput.stdout(
        CLILocalized.format("cli.status.group.labelControllers", controllers.count)
      )
      for controller in controllers {
        let identity = deviceIdentity(
          vendorID: controller.vendorID,
          productID: controller.productID
        )
        CLIOutput.stdout(
          "  \(identity)  \(controller.name)  \(controller.connection)  \(controller.id)"
        )
        if controller.paused {
          CLIOutput.stdout("    " + CLILocalized.text("ui.controllers.paused.value"))
        }
        printMapping(controller.inputMapping)
      }
    }
    if let unbound = report.unboundDevices, !unbound.isEmpty {
      CLIOutput.stdout("")
      CLIOutput.stdout(
        CLILocalized.format("cli.status.group.labelUnbound", unbound.count)
      )
      for device in unbound {
        let identity = deviceIdentity(vendorID: device.vendorID, productID: device.productID)
        CLIOutput.stdout(
          "  \(identity)  \(device.connection)  \(device.reason.map(CommandLineName.kebab) ?? "")"
        )
        if let reason = device.reason.flatMap(ProtocolBindingReason.init(rawValue:)) {
          CLIOutput.stdout("    \(CLILocalized.text(reason.explanationKey))")
          CLIOutput.stdout("    \(CLILocalized.text(reason.nextStepKey))")
        }
        printMapping(device.inputMapping)
      }
    }
    if let passThrough = report.passThroughDevices, !passThrough.isEmpty {
      CLIOutput.stdout("")
      CLIOutput.stdout(
        CLILocalized.format(
          "platform.macos.cli.status.group.labelPassThrough",
          passThrough.count
        )
      )
      for device in passThrough {
        let identity = deviceIdentity(vendorID: device.vendorID, productID: device.productID)
        CLIOutput.stdout("  \(identity)  \(device.connection)")
      }
    }
    if !report.skippedRecords.isEmpty {
      CLIOutput.stdout("")
      CLIOutput.stdout(
        CLILocalized.format(
          "cli.status.group.labelSkippedRecords",
          report.skippedRecords.count
        )
      )
      for skipped in report.skippedRecords {
        CLIOutput.stdout("  \(skipped.file)  \(skipped.problem)")
      }
    }
    if let ignored = report.ignoredDefaults {
      CLIOutput.stdout("")
      CLIOutput.stdout(CLILocalized.text("cli.status.group.labelIgnoredDefaults"))
      CLIOutput.stdout("  \(ignored.file)  \(ignored.problem)")
    }
    if !report.skippedVirtualDevices.isEmpty {
      CLIOutput.stdout("")
      CLIOutput.stdout(
        CLILocalized.format(
          "cli.status.group.labelSkippedVirtualDevices",
          report.skippedVirtualDevices.count
        )
      )
      for skipped in report.skippedVirtualDevices {
        CLIOutput.stdout("  \(skipped.file)  \(skipped.problem)")
      }
    }
  }
}
