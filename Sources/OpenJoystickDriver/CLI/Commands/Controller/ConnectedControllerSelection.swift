import Foundation
import OpenJoystickDriverKit

enum ConnectedControllerSelection {
  static func resolve(
    devices: [ApplicationServiceDeviceDescription],
    vendorID: UInt16? = nil,
    productID: UInt16? = nil,
    runtimeIdentifier: String? = nil
  ) throws -> ApplicationServiceDeviceDescription {
    guard (vendorID == nil) == (productID == nil) else {
      throw Failure(
        CLILocalized.text(
          "cli.controller.selection.vid_pid_pair",
          "Pass both VID and PID, or omit both."
        )
      )
    }

    let candidates = devices.filter { device in
      guard let vendorID, let productID else { return true }
      return device.vendorID == vendorID && device.productID == productID
    }

    if let runtimeIdentifier {
      let matches = candidates.filter { $0.runtimeIdentifier == runtimeIdentifier }
      guard matches.count == 1, let device = matches.first else {
        if matches.count > 1 {
          throw Failure(
            CLILocalized.text(
              "cli.controller.selection.device_ambiguous",
              "The --device selector is ambiguous for multiple connected controllers."
            )
          )
        }
        throw Failure(
          CLILocalized.format(
            "cli.controller.selection.device_missing",
            "No connected controller matches --device %@.",
            runtimeIdentifier
          )
        )
      }
      return device
    }

    switch candidates.count {
    case 1: return candidates[0]
    case 0:
      if let vendorID, let productID {
        throw Failure(
          CLILocalized.format(
            "cli.controller.selection.vid_pid_missing",
            "No connected controller matches %@:%@.",
            hex(vendorID),
            hex(productID)
          )
        )
      }
      throw Failure(
        CLILocalized.text("cli.controller.selection.none", "No controller is connected.")
      )
    default:
      let choices = candidates.map { device in
        "\(hex(device.vendorID)) \(hex(device.productID)) "
          + "--device \(device.runtimeIdentifier) \(device.name)"
      }.joined(separator: "\n  ")
      throw Failure(
        CLILocalized.format(
          "cli.controller.selection.multiple",
          "Multiple controllers match. Select one with --device:\n  %@",
          choices
        )
      )
    }
  }

  struct Failure: LocalizedError, Sendable {
    let message: String

    init(_ message: String) { self.message = message }

    var errorDescription: String? { message }
  }

  private static func hex(_ value: UInt16) -> String { String(format: "0x%04X", value) }
}
