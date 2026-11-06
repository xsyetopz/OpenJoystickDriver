import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `CONTROLLER` argument: a ``ControllerReference``.
///
/// That is a session token (`E-…`) from `ojd controller list`, which lasts until the controller is
/// unplugged; a port key (`U-…`), which lasts while the controller stays on the same port; or
/// `VVVV:PPPP` when exactly one connected controller has that vendor and product ID.
struct ControllerSelector: ExpressibleByArgument, Equatable, Sendable {
  /// The parsed reference.
  let reference: ControllerReference
  /// The argument as typed, for messages.
  let text: String

  /// Parses `argument` as a controller reference; fails when it is not one.
  init?(argument: String) {
    guard let reference = ControllerReference(argument) else { return nil }
    text = argument
    self.reference = reference
  }

  /// Uses the shell's default completion.
  static var defaultCompletionKind: CompletionKind { .default }

  /// The one connected controller that this selector names.
  ///
  /// - Throws: ``CLIFailure`` with exit code 1 that lists the candidates when none or several
  ///   match.
  func resolve(
    in devices: [ApplicationServiceDeviceDescription]
  ) throws -> ApplicationServiceDeviceDescription {
    let matches = reference.matches(in: devices)
    if matches.count == 1, let device = matches.first { return device }
    let message: String
    let listed: [ApplicationServiceDeviceDescription]
    if matches.isEmpty {
      listed = devices
      message =
        devices.isEmpty
        ? CLILocalized.format(
          "cli.controller.group.selectorNoneConnected",
          text
        )
        : CLILocalized.format(
          "cli.controller.group.selectorNotFound",
          text
        )
    } else {
      listed = matches
      message = CLILocalized.plural(
        "cli.controller.group.selectorAmbiguous",
        text,
        matches.count
      )
    }
    let lines = listed.map { device in
      let ids = [device.sessionToken.rawValue] + [device.portKey?.rawValue].compactMap { $0 }
      return "  \(ids.joined(separator: "  "))  \(device.identity)  \(device.name)"
    }
    throw CLIFailure(.notFound, ([message] + lines).joined(separator: "\n"))
  }

  /// Reads the connected controllers from the service and resolves this selector.
  ///
  /// - Throws: ``CLIFailure`` when the service is unreachable, or when none or several match.
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
