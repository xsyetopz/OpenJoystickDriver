/// The road OJD takes to reach one controller, as its record decides.
public enum ControllerAccessRoute: String, Codable, CaseIterable, Sendable {
  /// OJD's signed USB extension claims the controller.
  case extensionOwned
  /// OJD reads the controller through raw USB access.
  case rawAccess
  /// The system HID stack serves the controller.
  case system
}

extension DeviceRuntimeProfile {
  /// The access route of this record: a record `route` of `ExtensionOwned` wins, then the
  /// raw-USB families, and everything else stays with the system.
  public var accessRoute: ControllerAccessRoute {
    if route == .extensionOwned { return .extensionOwned }
    return usesRawUSB ? .rawAccess : .system
  }
}
