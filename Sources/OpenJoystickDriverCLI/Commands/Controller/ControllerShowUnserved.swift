import Foundation
import OpenJoystickDriverKit

/// The `ojd controller show --json` result for a connected device that OJD does not serve, with
/// `kind` `UnservedController`.
struct UnservedControllerReport: Encodable, Equatable {
  /// The USB vendor ID.
  let vendorID: Int
  /// The USB product ID.
  let productID: Int
  /// How the device connects.
  let connection: String
  /// How OJD reaches the device.
  let accessBackend: String
  /// Why OJD does not serve the device.
  let reason: String
  /// The command that drafts a record; absent unless the device is a HID pad.
  let draftCommand: String?
  /// The command that captures the packets; absent unless the reason is `NoProtocolMatch`.
  let captureCommand: String?

  /// The sentence that says why, in the language of the terminal; not part of the output.
  let explanation: String
  /// The sentence that says what to do, in the language of the terminal; not part of the output.
  let nextStep: String

  /// The keys of the output.
  private enum CodingKeys: String, CodingKey {
    case vendorID, productID, connection, accessBackend, reason, draftCommand, captureCommand
  }

  /// Describes `device`.
  init(_ device: ApplicationServiceUnboundDevice) {
    vendorID = Int(device.vendorID)
    productID = Int(device.productID)
    connection = device.connection
    accessBackend = device.accessBackend.rawValue
    reason = device.reason.rawValue
    draftCommand = device.draftCommand
    captureCommand = device.captureCommand
    explanation = CLILocalized.text(device.reason.explanationKey)
    nextStep = CLILocalized.text(device.reason.nextStepKey)
  }

  /// Prints the report in the format of the running command.
  func print() throws {
    switch CLIContext.current.format {
    case .json: try CLIOutput.json(self, kind: "UnservedController")
    case .plain:
      CLIOutput.plain(
        [
          ["identity", deviceIdentity(vendorID: vendorID, productID: productID)],
          ["connection", connection],
          ["reason", CommandLineName.kebab(reason)],
          draftCommand.map { ["draft-command", $0] },
          captureCommand.map { ["capture-command", $0] },
        ].compactMap { $0 }
      )
    case .human:
      var rows = [
        (
          CLILocalized.text("cli.controller.show.labelIdentity"),
          deviceIdentity(vendorID: vendorID, productID: productID)
        ),
        (CLILocalized.text("cli.controller.show.labelConnection"), connection),
        (CLILocalized.text("cli.controller.show.labelNotServed"), explanation),
        (CLILocalized.text("cli.controller.show.labelNextStep"), nextStep),
      ]
      if let draftCommand {
        rows.append((CLILocalized.text("cli.controller.show.labelDraftCommand"), draftCommand))
      }
      if let captureCommand {
        rows.append((CLILocalized.text("cli.controller.show.labelCaptureCommand"), captureCommand))
      }
      let width = rows.map(\.0.count).max() ?? 0
      for (label, value) in rows {
        CLIOutput.stdout(label.padding(toLength: width, withPad: " ", startingAt: 0) + "  " + value)
      }
    }
  }
}
