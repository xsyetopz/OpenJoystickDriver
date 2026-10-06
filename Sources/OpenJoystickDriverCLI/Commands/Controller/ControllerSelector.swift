import ArgumentParser
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverService

/// The `CONTROLLER` argument: an ID from `ojd controller list`, or `VVVV:PPPP` when exactly one
/// connected controller has that vendor and product ID. An ID lasts until the service restarts and
/// can change when the controller is unplugged and replugged (see `RuntimeDeviceIdentity`). A unit
/// ID (`U-…`) lasts while the controller stays on the same port (see ``UnitIdentity``).
struct ControllerSelector: ExpressibleByArgument, Equatable, Sendable {
  let kind: ControllerSelection
  let text: String

  init?(argument: String) {
    guard let kind = ControllerSelection(argument) else { return nil }
    text = argument
    self.kind = kind
  }

  static var defaultCompletionKind: CompletionKind { .default }

  /// The one connected controller this selector names.
  ///
  /// Throws a failure with exit code 1 that lists the candidates when none or several match.
  func resolve(
    in devices: [ApplicationServiceDeviceDescription]
  ) throws -> ApplicationServiceDeviceDescription {
    let matches = kind.matches(in: devices)
    if matches.count == 1, let device = matches.first { return device }
    let message: String
    let listed: [ApplicationServiceDeviceDescription]
    if matches.isEmpty {
      listed = devices
      message =
        devices.isEmpty
        ? CLILocalized.format(
          "cli.controller.selector.none_connected",
          text
        )
        : CLILocalized.format(
          "cli.controller.selector.not_found",
          text
        )
    } else {
      listed = matches
      message = CLILocalized.format(
        "cli.controller.selector.ambiguous",
        text,
        matches.count
      )
    }
    let lines = listed.map { "  \($0.runtimeIdentifier)  \($0.identity)  \($0.name)" }
    throw CLIFailure(.notFound, ([message] + lines).joined(separator: "\n"))
  }

  /// Reads the connected controllers from the service and resolves this selector.
  func resolve(
    with client: ApplicationServiceClient
  ) async throws -> ApplicationServiceDeviceDescription {
    try resolve(in: try await client.getStatus().connectedDevices)
  }
}

extension ApplicationServiceDeviceDescription {
  /// `VVVV:PPPP` for this controller.
  var identity: String { deviceIdentity(vendorID: Int(vendorID), productID: Int(productID)) }
}
