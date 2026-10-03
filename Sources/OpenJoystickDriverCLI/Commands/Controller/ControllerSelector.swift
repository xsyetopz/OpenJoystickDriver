import ArgumentParser
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverService

/// The `CONTROLLER` argument: an ID from `ojd controller list`, or `VVVV:PPPP` when exactly one
/// connected controller has that vendor and product ID. An ID lasts until the service restarts and
/// can change when the controller is unplugged and replugged (see `RuntimeDeviceIdentity`). A unit
/// ID (`U-…`) lasts while the controller stays on the same port (see ``UnitIdentity``).
struct ControllerSelector: ExpressibleByArgument, Equatable, Sendable {
  enum Kind: Equatable, Sendable {
    case id(String)
    case model(vendorID: UInt16, productID: UInt16)
  }

  let kind: Kind
  let text: String

  init?(argument: String) {
    guard !argument.isEmpty else { return nil }
    text = argument
    kind = Self.model(argument).map { .model(vendorID: $0.0, productID: $0.1) } ?? .id(argument)
  }

  static var defaultCompletionKind: CompletionKind { .default }

  /// `VVVV:PPPP`, four hex digits each, case-insensitive.
  static func model(_ text: String) -> (UInt16, UInt16)? {
    parseControllerModel(text).map { ($0.vendorID, $0.productID) }
  }

  /// The one connected controller this selector names.
  ///
  /// Throws a failure with exit code 1 that lists the candidates when none or several match.
  func resolve(
    in devices: [ApplicationServiceDeviceDescription]
  ) throws -> ApplicationServiceDeviceDescription {
    let matches: [ApplicationServiceDeviceDescription]
    switch kind {
    case .id(let id):
      matches = devices.filter { $0.runtimeIdentifier == id || $0.unitIdentifier == id }
    case .model(let vendorID, let productID):
      matches = devices.filter { $0.vendorID == vendorID && $0.productID == productID }
    }
    if matches.count == 1, let device = matches.first { return device }
    let message: String
    let listed: [ApplicationServiceDeviceDescription]
    if matches.isEmpty {
      listed = devices
      message =
        devices.isEmpty
        ? CLILocalized.format(
          "cli.controller.selector.none_connected",
          "No controller matches '%@', because none is connected. Connect one and run "
            + "'ojd controller list'.",
          text
        )
        : CLILocalized.format(
          "cli.controller.selector.not_found",
          "No connected controller matches '%@'. Use an ID or VVVV:PPPP from this list:",
          text
        )
    } else {
      listed = matches
      message = CLILocalized.format(
        "cli.controller.selector.ambiguous",
        "'%@' matches %lld controllers. Use one of these IDs:",
        text,
        matches.count
      )
    }
    let lines = listed.map { "  \($0.runtimeIdentifier)  \($0.identity)  \($0.name)" }
    throw CLIFailure(.failure, ([message] + lines).joined(separator: "\n"))
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
