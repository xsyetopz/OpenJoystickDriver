import ArgumentParser
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverService

struct StatusCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "status",
    abstract: CLILocalized.text(
      "cli.status.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.status.discussion"
    )
  )

  /// Reads the DriverKit extension state; tests replace it to avoid `systemextensionsctl`.
  @TaskLocal
  static var extensionProbe: @Sendable () -> ExtensionStatus = {
    ExtensionProbe.currentStatus(
      bundleURL: ServiceStartCommand.applicationBundleURL() ?? Bundle.main.bundleURL
    )
  }

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let payload: ApplicationServiceStatusPayload?
      do { payload = try await ServiceConnection.request { try await $0.getStatus() } } catch let
        failure as CLIFailure where failure.code == .serviceUnavailable
      { payload = nil }
      let records = RecordStore.load()
      let report = StatusReport(
        payload: payload,
        extensionStatus: Self.extensionProbe(),
        skippedRecords: records.problems.map(SkippedRecord.init),
        ignoredDefaults: SkippedRecord(records.defaults),
        skippedPersonas: RecordStore.personaFiles().filter { $0.problem != nil }
          .map(SkippedRecord.init)
      )
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(report)
      case .plain: CLIOutput.plain(Self.plainRows(report))
      case .human: Self.printHuman(report)
      }
    }
  }

  static func plainRows(_ report: StatusReport) -> [[String]] {
    var rows = [
      ["service", report.service.state.rawValue, report.service.version ?? ""],
      ["extension", report.extension.bundle.rawValue, report.extension.registration.rawValue],
    ]
    if let permissions = report.permissions {
      rows.append(["permission", "input-monitoring", permissions.inputMonitoring.rawValue])
      rows.append(["permission", "accessibility", permissions.accessibility.rawValue])
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
    }
    for device in report.unboundDevices ?? [] {
      rows.append([
        "unbound", deviceIdentity(vendorID: device.vendorID, productID: device.productID),
        device.connection, device.reason ?? "",
      ])
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
    for skipped in report.skippedPersonas {
      rows.append(["skipped-persona", skipped.file, skipped.problem])
    }
    return rows
  }

  private static func printHuman(_ report: StatusReport) {
    var rows: [(String, String)] = [
      (
        CLILocalized.text("cli.status.label.service"),
        report.service.state.rawValue + (report.service.version.map { " (\($0))" } ?? "")
      ),
      (
        CLILocalized.text("cli.status.label.extension"),
        "\(report.extension.bundle.rawValue), \(report.extension.registration.rawValue)"
      ),
    ]
    if let permissions = report.permissions {
      rows.append(
        (
          CLILocalized.text("cli.status.label.input_monitoring"),
          permissions.inputMonitoring.rawValue
        )
      )
      rows.append(
        (
          CLILocalized.text("cli.status.label.accessibility"),
          permissions.accessibility.rawValue
        )
      )
    }
    if let virtual = report.virtualDevice {
      rows.append(
        (
          CLILocalized.text("cli.status.label.virtual_device"),
          virtual.status ?? (virtual.enabled == true ? "enabled" : "disabled")
        )
      )
      if let error = virtual.overrideError {
        rows.append((CLILocalized.text("cli.status.label.override_error"), error))
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
          "cli.status.start_hint"
        )
      )
    }
  }

  private static func printDevices(_ report: StatusReport) {
    if let controllers = report.controllers {
      CLIOutput.stdout("")
      CLIOutput.stdout(
        CLILocalized.format("cli.status.label.controllers", controllers.count)
      )
      for controller in controllers {
        let identity = deviceIdentity(
          vendorID: controller.vendorID,
          productID: controller.productID
        )
        CLIOutput.stdout(
          "  \(identity)  \(controller.name)  \(controller.connection)  \(controller.id)"
        )
      }
    }
    if let unbound = report.unboundDevices, !unbound.isEmpty {
      CLIOutput.stdout("")
      CLIOutput.stdout(
        CLILocalized.format("cli.status.label.unbound", unbound.count)
      )
      for device in unbound {
        let identity = deviceIdentity(vendorID: device.vendorID, productID: device.productID)
        CLIOutput.stdout("  \(identity)  \(device.connection)  \(device.reason ?? "")")
      }
    }
    if let passThrough = report.passThroughDevices, !passThrough.isEmpty {
      CLIOutput.stdout("")
      CLIOutput.stdout(
        CLILocalized.format(
          "cli.status.label.pass_through",
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
          "cli.status.label.skipped_records",
          report.skippedRecords.count
        )
      )
      for skipped in report.skippedRecords {
        CLIOutput.stdout("  \(skipped.file)  \(skipped.problem)")
      }
    }
    if let ignored = report.ignoredDefaults {
      CLIOutput.stdout("")
      CLIOutput.stdout(CLILocalized.text("cli.status.label.ignored_defaults"))
      CLIOutput.stdout("  \(ignored.file)  \(ignored.problem)")
    }
    if !report.skippedPersonas.isEmpty {
      CLIOutput.stdout("")
      CLIOutput.stdout(
        CLILocalized.format(
          "cli.status.label.skipped_personas",
          report.skippedPersonas.count
        )
      )
      for skipped in report.skippedPersonas {
        CLIOutput.stdout("  \(skipped.file)  \(skipped.problem)")
      }
    }
  }
}
