public import Foundation

extension Notification.Name {
  /// Posted in-process after anything `getStatus` or the remapping snapshot reports changes.
  public static let ojdServiceStatusDidChange = Notification.Name(
    "OpenJoystickDriver.serviceStatusDidChange"
  )
}

extension NotificationCenter {
  /// Announces that the service's reported status changed. `source` is the object whose state
  /// changed, so a test can observe one source.
  public static func postServiceStatusChanged(from source: AnyObject) {
    Self.default.post(name: .ojdServiceStatusDidChange, object: source)
  }
}

/// Observed result of acquiring one physical HID interface, independent of virtual output.
public enum HIDInputOwnership: String, Codable, Equatable, Sendable {
  /// The ownership has not been observed.
  case unknown = "Unknown"
  /// OJD owns the interface exclusively.
  case exclusive = "Exclusive"
  /// OJD holds the interface, but other clients can read it.
  case shared = "Shared"
  /// The system refused access to the interface.
  case accessDenied = "AccessDenied"
  /// Another client holds the interface.
  case ownedByAnotherClient = "OwnedByAnotherClient"
  /// The attempt to acquire the interface failed.
  case acquisitionFailed = "AcquisitionFailed"

  /// Every interface must be exclusively owned before the location can promise isolation.
  static func combined(_ observations: [Self]) -> Self {
    observations.min { $0.priority < $1.priority } ?? .unknown
  }

  /// The rank of the state when states combine; the lowest rank wins.
  private var priority: Int {
    switch self {
    case .ownedByAnotherClient: 0
    case .accessDenied: 1
    case .acquisitionFailed: 2
    case .unknown: 3
    case .shared: 4
    case .exclusive: 5
    }
  }
}

/// A semantic value decoded by the active app HID backend from one input element.
public struct HIDElementValue: Sendable, Equatable {
  /// The ID of the report that holds the element; nil when the device uses no report IDs.
  public let reportID: UInt32?
  /// The HID usage page of the element.
  public let usagePage: UInt32
  /// The HID usage of the element.
  public let usage: UInt32
  /// The least value the element reports.
  public let logicalMinimum: Int
  /// The greatest value the element reports.
  public let logicalMaximum: Int
  /// The value of the element.
  public let integerValue: Int

  /// Creates a value from its fields.
  public init(
    usagePage: UInt32,
    usage: UInt32,
    logicalMinimum: Int,
    logicalMaximum: Int,
    integerValue: Int,
    reportID: UInt32? = nil
  ) {
    self.reportID = reportID
    self.usagePage = usagePage
    self.usage = usage
    self.logicalMinimum = logicalMinimum
    self.logicalMaximum = logicalMaximum
    self.integerValue = integerValue
  }
}

/// An event from the active app HID backend for a class-0x03 controller.
///
/// ``HIDManager`` sends these to ``DeviceManager`` to report when a
/// HID controller is plugged in, unplugged, or sends an input report.
public struct HIDDeviceConnection: Equatable, Sendable {
  /// Unique to one observed connect-to-disconnect lifetime, even if a backend reuses its route ID.
  public let connectionID: UUID
  /// Exact immutable physical facts captured when this connection was admitted.
  public let physicalDevice: PhysicalDevice
  /// Backend routing key, distinct from the optional physical location in `physicalDevice`:
  /// an IOKit location without an interface for IOHID, or a GATT peripheral.
  public let routingAddress: ControllerConnectionAddress

  /// Creates a connection; `connectionID` defaults to a new UUID.
  public init(
    connectionID: UUID = UUID(),
    physicalDevice: PhysicalDevice,
    routingAddress: ControllerConnectionAddress
  ) {
    self.connectionID = connectionID
    self.physicalDevice = physicalDevice
    self.routingAddress = routingAddress
  }

  /// How the host reaches this connection: Core Bluetooth for a GATT peripheral, IOHID otherwise.
  public var accessBackend: DeviceAccessBackend {
    if case .gattPeripheral = routingAddress { .gatt } else { .hid }
  }
}

/// What a HID access backend reports about a controller.
public enum HIDDeviceEvent: Sendable {
  /// A HID controller was plugged in with the immutable facts available from its
  /// OS HID service. `routingAddress` remains the backend's runtime routing key;
  /// the physical location in `physicalDevice` can be unavailable.
  case connected(connection: HIDDeviceConnection, ownership: HIDInputOwnership = .unknown)
  /// Access changed while the physical controller remains connected.
  case ownershipChanged(address: ControllerConnectionAddress, ownership: HIDInputOwnership)
  /// The active HID access stream failed. Cancellation is not reported as an access failure.
  case accessFailure(PhysicalHIDFailure)
  /// A HID controller was unplugged; the event carries the connection that `connected` carried.
  case disconnected(connection: HIDDeviceConnection)
  /// The controller sent a raw input report (button presses, stick positions, etc.) on the
  /// connection `connectionID` at routing address `address`.
  case inputReport(
    address: ControllerConnectionAddress,
    connectionID: UUID,
    reportID: UInt8,
    data: Data
  )
  /// IOKit decoded one descriptor-defined input element of the connection `connectionID`.
  case inputValue(address: ControllerConnectionAddress, connectionID: UUID, value: HIDElementValue)
}
