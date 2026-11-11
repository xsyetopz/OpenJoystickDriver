import Foundation
import OpenJoystickDriverKit

/// The text of the confirmation that precedes closing a controller's Bluetooth link, shown by the
/// Controller menu, the status menu and the controller list.
struct WirelessDisconnectConfirmation: Equatable {
  /// The title of the confirmation.
  let title: String
  /// The message of the confirmation, with the controller's name.
  let message: String
  /// The title of the confirming button.
  let confirmTitle: String

  /// Creates the confirmation for the controller.
  ///
  /// - Parameter controllerName: The name of the controller.
  init(controllerName: String) {
    title = OJDLocalized.string("ui.controllers.disconnectWirelessConfirmTitle")
    message = OJDLocalized.formatted(
      "ui.controllers.disconnectWirelessConfirmMessage",
      controllerName
    )
    confirmTitle = OJDLocalized.string("ui.controllers.disconnectWirelessConfirm")
  }
}

/// A pending Bluetooth link closure: the controller captured when the user asked, so the
/// confirmed action still has it after the presentation state has been reset.
struct WirelessDisconnectRequest: Identifiable {
  /// The controller.
  let device: ApplicationServiceDeviceDescription
  /// The confirmation to show.
  let confirmation: WirelessDisconnectConfirmation

  /// The session token of the controller, which names the request.
  var id: String { device.sessionToken.rawValue }

  /// Creates the request for the controller.
  ///
  /// - Parameter device: The controller.
  init(device: ApplicationServiceDeviceDescription) {
    self.device = device
    confirmation = WirelessDisconnectConfirmation(controllerName: device.name)
  }
}
