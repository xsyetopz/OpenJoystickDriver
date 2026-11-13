import OpenJoystickDriverKit

extension ApplicationServiceDeviceDescription {
  /// Whether the controller connects over USB, so its input and output endpoints are USB endpoints.
  ///
  /// `connection` is the IOHID transport name, which is "USB" for a USB controller.
  var hasUSBEndpoints: Bool { connection == "USB" }
}
