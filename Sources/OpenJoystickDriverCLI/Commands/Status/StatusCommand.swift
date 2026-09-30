import ArgumentParser
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverService

struct StatusCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "status",
    abstract: CLILocalized.text(
      "cli.status.abstract",
      "Show the service, extension, permissions, and connected controllers."
    ),
    discussion: CLILocalized.text(
      "cli.status.discussion",
      "Works when the service is stopped: it reports the service as stopped and exits 0."
    )
  )

  /// Reads the DriverKit extension state; tests replace it to avoid `systemextensionsctl`.
  @TaskLocal
  static var extensionProbe: @Sendable () -> ExtensionStatus = {
    ExtensionProbe.currentStatus(
      bundleURL: ServiceStartCommand.applicationBundleURL() ?? Bundle.main.bundleURL
    )
  }

  @OptionGroup
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let payload: ApplicationServiceStatusPayload?
      do { payload = try await ServiceConnection.request { try await $0.getStatus() } } catch let
        failure as CLIFailure where failure.code == .serviceUnavailable
      { payload = nil }
      let report = StatusReport(
        payload: payload,
        extensionStatus: Self.extensionProbe(),
        skippedRecords: RecordStore.load().problems.map(SkippedRecord.init)
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
      rows.append(["permission", "input-monitoring", permissions.inputMonitoring])
      rows.append(["permission", "accessibility", permissions.accessibility])
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
    return rows
  }

  private static func printHuman(_ report: StatusReport) {
    var rows: [(String, String)] = [
      (
        CLILocalized.text("cli.status.label.service", "Service"),
        report.service.state.rawValue + (report.service.version.map { " (\($0))" } ?? "")
      ),
      (
        CLILocalized.text("cli.status.label.extension", "Extension"),
        "\(report.extension.bundle.rawValue), \(report.extension.registration.rawValue)"
      ),
    ]
    if let permissions = report.permissions {
      rows.append(
        (
          CLILocalized.text("cli.status.label.input_monitoring", "Input Monitoring"),
          permissions.inputMonitoring
        )
      )
      rows.append(
        (
          CLILocalized.text("cli.status.label.accessibility", "Accessibility"),
          permissions.accessibility
        )
      )
    }
    if let virtual = report.virtualDevice {
      rows.append(
        (
          CLILocalized.text("cli.status.label.virtual_device", "Virtual gamepad"),
          virtual.status ?? (virtual.enabled == true ? "enabled" : "disabled")
        )
      )
      if let error = virtual.overrideError {
        rows.append((CLILocalized.text("cli.status.label.override_error", "Override error"), error))
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
          "cli.status.start_hint",
          "Controllers and permissions appear when the service runs: 'ojd service start'."
        )
      )
    }
  }

  private static func printDevices(_ report: StatusReport) {
    if let controllers = report.controllers {
      CLIOutput.stdout("")
      CLIOutput.stdout(
        CLILocalized.format("cli.status.label.controllers", "Controllers (%lld)", controllers.count)
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
        CLILocalized.format("cli.status.label.unbound", "Unsupported devices (%lld)", unbound.count)
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
          "Left to macOS (%lld)",
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
          "Skipped controller records (%lld)",
          report.skippedRecords.count
        )
      )
      for skipped in report.skippedRecords {
        CLIOutput.stdout("  \(skipped.file)  \(skipped.problem)")
      }
    }
  }
}
