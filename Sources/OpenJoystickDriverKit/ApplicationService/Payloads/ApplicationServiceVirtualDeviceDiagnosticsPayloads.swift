import Foundation

/// Redacted serial number state for a HID device.
public enum ApplicationServiceSerialKind: String, Codable, Sendable {
  case none
  case ojdUserSpace
  case present
}

/// Safe (non-sensitive) snapshot of a HID "GamePad" device as seen by IOKit.
public struct ApplicationServiceHIDGamepadSnapshot: Codable, Sendable, Hashable {
  public let vendorID: UInt16
  public let productID: UInt16
  public let product: String?
  public let transport: String?
  public let locationID: UInt32?
  public let serialKind: ApplicationServiceSerialKind
  public let ioUserClass: String?

  /// True if this looks like an OJD app-owned virtual HID device.
  public let isOJDUserSpace: Bool
  /// True if Apple's GameController.framework says this HID device gets a GCController.
  public let isGameControllerSupported: Bool?

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
  public let userSpaceVirtualDeviceEnabled: Bool
  public let userSpaceVirtualDeviceStatus: VirtualOutputBackendStatus
  public let hidGamepads: [ApplicationServiceHIDGamepadSnapshot]

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
