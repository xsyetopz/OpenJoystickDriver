import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `--json` result of `ojd controller send`: the `details` of a `Success` status.
///
/// A write the controller does not take fails the command instead.
struct ControllerSendReport: Encodable, Equatable {
  /// The session ID of the controller.
  let controller: String
  /// `hidOutput`, `hidFeature` or `usbInterrupt`.
  let destination: String
  /// The HID report ID; nil for USB.
  let reportID: Int?
  /// The USB OUT endpoint; nil for HID.
  let endpoint: Int?
  /// The bytes written, as uppercase hex pairs separated by spaces.
  let bytes: String
  /// How the controller took the write.
  let outcome: String
}

/// The `ojd controller send` command: writes raw bytes to a controller.
struct ControllerSendCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "send",
    abstract: CLILocalized.text("cli.controller.send.abstract"),
    discussion: CLILocalized.text("cli.controller.send.discussion") + "\n\n"
      + CLILocalized.text("cli.controller.send.examples")
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// The controller to write to.
  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  /// The bytes of the whole report as hex pairs, in one argument or several.
  @Argument(
    help: ArgumentHelp(CLILocalized.text("cli.controller.send.bytes"), valueName: "bytes")
  )
  var bytes: [String]

  /// `--feature`: send a HID feature report instead of an output report.
  @Flag(help: ArgumentHelp(CLILocalized.text("cli.controller.send.feature")))
  var feature = false

  /// `--report-id`: the report ID of a numbered report, from 1 to 255.
  @Option(
    name: .customLong("report-id"),
    help: ArgumentHelp(CLILocalized.text("cli.controller.send.reportID"), valueName: "1-255")
  )
  var reportID: UInt8?

  /// `--usb-endpoint`: send a USB interrupt OUT packet to this endpoint.
  @Option(
    name: .customLong("usb-endpoint"),
    help: ArgumentHelp(CLILocalized.text("cli.controller.send.usbEndpoint"), valueName: "0-255")
  )
  var usbEndpoint: UInt8?

  /// The write the arguments describe, or nil when they do not form one.
  ///
  /// The write may still fail ``ControllerRawOutput/isValid`` only through its bytes, which
  /// ``validate()`` reports first.
  var output: ControllerRawOutput? {
    guard let parsed = ControllerRawOutput.parseHex(bytes.joined(separator: " ")) else {
      return nil
    }
    let destination: ControllerRawOutput.Destination =
      usbEndpoint != nil ? .usbInterrupt : feature ? .hidFeature : .hidOutput
    return ControllerRawOutput(
      destination: destination,
      reportID: reportID ?? 0,
      endpoint: usbEndpoint,
      bytes: parsed
    )
  }

  /// Checks the options against each other and the bytes against the report ID.
  ///
  /// - Throws: ``ValidationError`` for bytes that are not 1 to 64 hex pairs, a report ID outside
  ///   1 to 255 or different from the first byte, and an endpoint combined with `--feature` or
  ///   `--report-id`.
  func validate() throws {
    if usbEndpoint != nil, feature || reportID != nil {
      throw ValidationError(CLILocalized.text("cli.controller.send.errorUSB"))
    }
    guard let output, output.bytes.count <= ControllerRawOutput.maxByteCount else {
      throw ValidationError(CLILocalized.text("cli.controller.send.errorBytes"))
    }
    guard output.isValid, reportID != 0 else {
      throw ValidationError(CLILocalized.text("cli.controller.send.errorReportID"))
    }
  }

  /// Runs the command.
  func run() async throws {
    try await global.run {
      guard let output else {
        throw ValidationError(CLILocalized.text("cli.controller.send.errorBytes"))
      }
      let selector = controller
      let (device, result) = try await ServiceConnection.request { client in
        let device = try await selector.resolve(with: client)
        let result = try await client.sendRawControllerOutput(
          output,
          for: .session(device.sessionToken)
        )
        return (device, result)
      }
      try ControllerOutput.check(
        result,
        name: "send",
        feature: CLILocalized.text("cli.controller.group.featureRaw"),
        device
      )
      let report = ControllerSendReport(
        controller: device.sessionToken.rawValue,
        destination: output.destination.rawValue,
        reportID: output.destination == .usbInterrupt ? nil : Int(output.reportID),
        endpoint: output.endpoint.map(Int.init),
        bytes: output.hex,
        outcome: result.outcome.rawValue
      )
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(CLIStatus(details: report))
      case .plain:
        CLIOutput.plain([
          [
            report.controller, report.destination, report.bytes,
            CommandLineName.kebab(report.outcome),
          ]
        ])
      case .human:
        CLIOutput.success(
          CLILocalized.format(
            "cli.controller.send.sent",
            String(output.bytes.count),
            device.name
          )
        )
      }
    }
  }
}
