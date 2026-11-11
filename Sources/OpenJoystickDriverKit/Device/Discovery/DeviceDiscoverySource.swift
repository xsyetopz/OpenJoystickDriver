/// The discovery route that owns a connected controller's pipeline.
public enum DeviceDiscoverySource: String, Codable, Sendable {
  /// The controller is reached through IOKit HID.
  case hid = "HID"
  /// The controller is reached as a raw USB service.
  case rawUSB = "RawUSB"
}
