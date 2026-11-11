import Foundation

/// Redacted serial number state for a HID device.
public enum ApplicationServiceSerialKind: String, Codable, Sendable {
  /// The device reports no serial number.
  case none = "None"
  /// The serial number marks the device as one that OJD's user-space virtual device published.
  case ojdUserSpace = "OJDUserSpace"
  /// The device reports a serial number of another origin; the report never includes it.
  case present = "Present"
}

/// Safe (non-sensitive) snapshot of a HID "GamePad" device as seen by IOKit.
public struct ApplicationServiceHIDGamepadSnapshot: Codable, Sendable, Hashable {
  /// The USB vendor ID.
  public let vendorID: UInt16
  /// The USB product ID.
  public let productID: UInt16
  /// The product name; nil when the device reports none.
  public let product: String?
  /// The transport, such as USB or Bluetooth; nil when the device reports none.
  public let transport: String?
  /// The location ID of the device; nil when it reports none.
  public let locationID: UInt32?
  /// Whether the device reports a serial number, and whose.
  public let serialKind: ApplicationServiceSerialKind
  /// The IOKit class of the device's user client; nil when the device reports none.
  public let ioUserClass: String?

  /// True if this looks like an OJD app-owned virtual HID device.
  public let isOJDUserSpace: Bool
  /// True if Apple's GameController.framework says this HID device gets a GCController.
  public let isGameControllerSupported: Bool?

  /// Creates the snapshot from its values.
  public init(
    vendorID: UInt16,
    productID: UInt16,
    product: String?,
    transport: String?,
    locationID: UInt32?,
    serialKind: ApplicationServiceSerialKind,
    ioUserClass: String?,
    isOJDUserSpace: Bool,
    isGameControllerSupported: Bool? = nil
  ) {
    self.vendorID = vendorID
    self.productID = productID
    self.product = product
    self.transport = transport
    self.locationID = locationID
    self.serialKind = serialKind
    self.ioUserClass = ioUserClass
    self.isOJDUserSpace = isOJDUserSpace
    self.isGameControllerSupported = isGameControllerSupported
  }
}

/// Diagnostics snapshot returned by
/// ``ApplicationServiceClient/getVirtualDeviceDiagnostics()``.
public struct ApplicationServiceVirtualDeviceDiagnosticsPayload: Codable, Sendable {
  /// Whether OJD's user-space virtual device is turned on.
  public let userSpaceVirtualDeviceEnabled: Bool
  /// The state of OJD's user-space virtual device backend.
  public let userSpaceVirtualDeviceStatus: VirtualOutputBackendStatus
  /// The HID gamepads that IOKit lists.
  public let hidGamepads: [ApplicationServiceHIDGamepadSnapshot]

  /// Creates the payload from its values.
  public init(
    userSpaceVirtualDeviceEnabled: Bool,
    userSpaceVirtualDeviceStatus: VirtualOutputBackendStatus,
    hidGamepads: [ApplicationServiceHIDGamepadSnapshot]
  ) {
    self.userSpaceVirtualDeviceEnabled = userSpaceVirtualDeviceEnabled
    self.userSpaceVirtualDeviceStatus = userSpaceVirtualDeviceStatus
    self.hidGamepads = hidGamepads
  }
}
