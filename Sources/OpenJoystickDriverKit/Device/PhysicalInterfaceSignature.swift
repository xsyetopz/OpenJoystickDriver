import CryptoKit
import Foundation

/// The kind of link a device interface uses, toward the host or on the controller side.
///
/// A ``PhysicalInterfaceSignature`` records the host-facing link and the controller-side link
/// separately. The UpperCamelCase `rawValue` is the one spelling in controller records, reports,
/// `--json` and the endpoint.
public enum PhysicalTransport: String, CaseIterable, Codable, Equatable, Sendable {
  /// A USB link.
  case usb = "USB"
  /// A Bluetooth Classic link.
  case bluetoothClassic = "BluetoothClassic"
  /// A Bluetooth Low Energy link.
  case bluetoothLE = "BluetoothLE"
  /// A link through a proprietary radio receiver, such as a vendor's wireless dongle.
  case proprietaryRadioReceiver = "ProprietaryRadioReceiver"
}

/// The access path OJD uses to reach a device interface: IOKit HID, raw USB through IOUSBHost or
/// the DEXT, or a Bluetooth LE GATT link through Core Bluetooth.
public enum DeviceAccessBackend: String, Codable, Equatable, Sendable {
  /// IOKit HID.
  case hid = "HID"
  /// Raw USB from the app through the IOUSBHost framework.
  case rawUSB = "RawUSB"
  /// Raw USB through the entitled USBDriverKit system extension.
  case usbExtension = "USBExtension"
  /// A Bluetooth LE GATT link through Core Bluetooth.
  case gatt = "GATT"

  /// Whether the backend reaches the device as raw USB, with no HID layer in between.
  public var usesRawUSB: Bool { self == .rawUSB || self == .usbExtension }

  /// Creates the backend that serves a raw USB `route`.
  public init(route: USBTransportRoute) {
    switch route {
    case .rawUSB: self = .rawUSB
    case .usbExtension: self = .usbExtension
    }
  }
}

/// The transfer type of a USB endpoint, as its descriptor reports it.
public enum USBEndpointTransferType: String, Equatable, Sendable {
  /// A control endpoint.
  case control = "Control"
  /// An isochronous endpoint.
  case isochronous = "Isochronous"
  /// A bulk endpoint.
  case bulk = "Bulk"
  /// An interrupt endpoint.
  case interrupt = "Interrupt"
  /// The descriptor reports no transfer type that this enumeration lists.
  case unknown = "Unknown"
}

/// The direction of a USB endpoint, seen from the host.
public enum USBEndpointDirection: String, Equatable, Sendable {
  /// Device to host.
  case `in` = "In"
  /// Host to device.
  case out = "Out"
}

/// The facts available for one USB endpoint; a descriptor field that is missing stays nil.
public struct PhysicalEndpointSignature: Equatable, Sendable {
  /// The endpoint address, with the direction in bit 7.
  public let address: UInt8?
  /// The direction of the endpoint.
  public let direction: USBEndpointDirection?
  /// The transfer type of the endpoint.
  public let transferType: USBEndpointTransferType?
  /// The maximum packet size in bytes.
  public let maxPacketSize: UInt16?
  /// The polling interval from the endpoint descriptor (`bInterval`).
  public let interval: UInt8?

  /// Creates an endpoint signature; every fact left nil is unknown.
  public init(
    address: UInt8? = nil,
    direction: USBEndpointDirection? = nil,
    transferType: USBEndpointTransferType? = nil,
    maxPacketSize: UInt16? = nil,
    interval: UInt8? = nil
  ) {
    self.address = address
    self.direction = direction
    self.transferType = transferType
    self.maxPacketSize = maxPacketSize
    self.interval = interval
  }
}

/// A usage page and usage reported by the HID API.
///
/// Each fact stays optional because IOHID can expose a partial usage pair.
public struct HIDUsageSignature: Equatable, Sendable {
  /// The HID usage page.
  public let usagePage: UInt32?
  /// The HID usage within the usage page.
  public let usage: UInt32?

  /// Creates a usage signature from the facts the HID API reported.
  public init(usagePage: UInt32? = nil, usage: UInt32? = nil) {
    self.usagePage = usagePage
    self.usage = usage
  }
}

/// The kind of a HID report.
public enum PhysicalHIDReportKind: String, Equatable, Sendable {
  /// A report that the device sends to the host.
  case input
  /// A report that the host sends to the device.
  case output
  /// A report that the host reads or writes on request.
  case feature
}

/// The report IDs and byte length that a HID backend exposes for one report kind.
public struct PhysicalHIDReportSignature: Equatable, Sendable {
  /// The kind of report this signature describes.
  public let kind: PhysicalHIDReportKind
  /// The numbered report IDs of this kind.
  ///
  /// Nil means the backend did not expose identifiers. An empty array means it enumerated this
  /// report kind and found no numbered report IDs.
  public let reportIDs: [UInt32]?
  /// The maximum report length of this kind, in bytes.
  public let maximumLengthBytes: UInt32?

  /// Creates a report signature of `kind`; every fact left nil is unknown.
  public init(
    kind: PhysicalHIDReportKind,
    reportIDs: [UInt32]? = nil,
    maximumLengthBytes: UInt32? = nil
  ) {
    self.kind = kind
    self.reportIDs = reportIDs
    self.maximumLengthBytes = maximumLengthBytes
  }
}

/// HID facts observed from a descriptor, usage collection, or report API.
public struct HIDLayoutSummary: Equatable, Sendable {
  /// Whether the interface has a game pad or joystick collection.
  ///
  /// Nil means the available API did not expose enough usage facts to decide.
  public let hasGamePadOrJoystickCollection: Bool?
  /// Whether the interface exposes elements that carry input.
  ///
  /// Nil means the backend could not enumerate elements.
  public let hasUsableElements: Bool?
  /// The primary usage of the interface.
  public let primaryUsage: HIDUsageSignature?
  /// The usages of the interface's collections.
  public let collectionUsages: [HIDUsageSignature]?
  /// The raw HID report descriptor bytes, when the backend exposes them.
  public let reportDescriptor: Data?
  /// The reports the backend enumerated for the interface.
  public let reports: [PhysicalHIDReportSignature]?
  /// The lowercase SHA-256 of ``reportDescriptor``, or nil without a descriptor.
  public let descriptorFingerprint: String?

  /// Creates a layout summary and derives ``descriptorFingerprint`` from `reportDescriptor`.
  public init(
    hasGamePadOrJoystickCollection: Bool? = nil,
    hasUsableElements: Bool? = nil,
    primaryUsage: HIDUsageSignature? = nil,
    collectionUsages: [HIDUsageSignature]? = nil,
    reportDescriptor: Data? = nil,
    reports: [PhysicalHIDReportSignature]? = nil
  ) {
    self.hasGamePadOrJoystickCollection = hasGamePadOrJoystickCollection
    self.hasUsableElements = hasUsableElements
    self.primaryUsage = primaryUsage
    self.collectionUsages = collectionUsages
    self.reportDescriptor = reportDescriptor
    self.reports = reports
    self.descriptorFingerprint = reportDescriptor.map(Self.fingerprint)
  }

  /// The lowercase hexadecimal SHA-256 digest of `data`.
  private static func fingerprint(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

/// The immutable facts available for one interface and alternate setting.
///
/// `hostTransport` describes the observed host-facing link. `physicalTransport` is the
/// controller-side link and stays nil unless evidence identifies it. `usbRoute` preserves the
/// access path OJD actually uses; ``DeviceAccessBackend/init(route:)`` names its access backend.
public struct PhysicalInterfaceSignature: Equatable, Sendable {
  /// The interface number (`bInterfaceNumber`).
  public let interfaceNumber: UInt8?
  /// The alternate setting (`bAlternateSetting`).
  public let alternateSetting: UInt8?
  /// The interface class code (`bInterfaceClass`).
  public let interfaceClass: UInt8?
  /// The interface subclass code (`bInterfaceSubClass`).
  public let interfaceSubclass: UInt8?
  /// The interface protocol code (`bInterfaceProtocol`).
  public let interfaceProtocol: UInt8?
  /// The value of the configuration that holds the interface (`bConfigurationValue`).
  public let configurationValue: UInt8?
  /// The observed host-facing link.
  public let hostTransport: PhysicalTransport?
  /// The controller-side link; nil unless evidence identifies it.
  public let physicalTransport: PhysicalTransport?
  /// The access path OJD uses to reach the interface.
  public let accessBackend: DeviceAccessBackend?
  /// The raw USB route that reaches the interface.
  public let usbRoute: USBTransportRoute?
  /// The endpoints of the interface.
  public let endpoints: [PhysicalEndpointSignature]?
  /// The HID facts of the interface.
  public let hidLayout: HIDLayoutSummary?

  /// Creates an interface signature; every fact left nil is unknown.
  public init(
    interfaceNumber: UInt8? = nil,
    alternateSetting: UInt8? = nil,
    interfaceClass: UInt8? = nil,
    interfaceSubclass: UInt8? = nil,
    interfaceProtocol: UInt8? = nil,
    configurationValue: UInt8? = nil,
    hostTransport: PhysicalTransport? = nil,
    physicalTransport: PhysicalTransport? = nil,
    accessBackend: DeviceAccessBackend? = nil,
    usbRoute: USBTransportRoute? = nil,
    endpoints: [PhysicalEndpointSignature]? = nil,
    hidLayout: HIDLayoutSummary? = nil
  ) {
    self.interfaceNumber = interfaceNumber
    self.alternateSetting = alternateSetting
    self.interfaceClass = interfaceClass
    self.interfaceSubclass = interfaceSubclass
    self.interfaceProtocol = interfaceProtocol
    self.configurationValue = configurationValue
    self.hostTransport = hostTransport
    self.physicalTransport = physicalTransport
    self.accessBackend = accessBackend
    self.usbRoute = usbRoute
    self.endpoints = endpoints
    self.hidLayout = hidLayout
  }
}

/// One enumerated physical device and the signature of each of its interfaces.
public struct PhysicalDevice: Equatable, Sendable {
  /// The address of the device's service.
  public let serviceAddress: ControllerConnectionAddress?
  /// The unique identifier the platform reports for the device, such as the HID physical device
  /// unique ID.
  public let platformUniqueIdentifier: String?
  /// The vendor ID.
  public let vendorID: UInt16?
  /// The product ID.
  public let productID: UInt16?
  /// The device release number (`bcdDevice`).
  public let deviceRelease: UInt16?
  /// The device class code (`bDeviceClass`).
  public let deviceClass: UInt8?
  /// The device subclass code (`bDeviceSubClass`).
  public let deviceSubclass: UInt8?
  /// The device protocol code (`bDeviceProtocol`).
  public let deviceProtocol: UInt8?
  /// The value of the active configuration.
  public let configurationValue: UInt8?
  /// The manufacturer string that the active OS property API returns, if available.
  public let manufacturer: String?
  /// The product name string.
  public let productName: String?
  /// The serial number string.
  public let serialNumber: String?
  /// The transport label that the active OS HID property API returns, if available.
  public let transportProperty: String?
  /// The IOKit location ID of the device's port.
  public let physicalLocationIdentifier: UInt32?
  /// The identifier of the device's parent device, when a backend provides one.
  public let stableParentDeviceIdentifier: String?
  /// The signature of each interface of the device.
  public let interfaces: [PhysicalInterfaceSignature]?
  /// Whether the running macOS already exposes this device as a native gamepad
  /// (`GCController.supportsHIDDevice`).
  ///
  /// OJD leaves such a device to macOS before classification.
  public let nativePassThrough: Bool
  /// Whether GameController lists this device as a gamepad (`GCController.supportsHIDDevice`).
  ///
  /// When OJD serves the device anyway, macOS publishes a second pad for it that gives no input.
  public let systemListsGameController: Bool

  /// Creates a physical device; every fact left nil is unknown.
  public init(
    serviceAddress: ControllerConnectionAddress? = nil,
    platformUniqueIdentifier: String? = nil,
    vendorID: UInt16? = nil,
    productID: UInt16? = nil,
    deviceRelease: UInt16? = nil,
    deviceClass: UInt8? = nil,
    deviceSubclass: UInt8? = nil,
    deviceProtocol: UInt8? = nil,
    configurationValue: UInt8? = nil,
    manufacturer: String? = nil,
    productName: String? = nil,
    serialNumber: String? = nil,
    transportProperty: String? = nil,
    physicalLocationIdentifier: UInt32? = nil,
    stableParentDeviceIdentifier: String? = nil,
    interfaces: [PhysicalInterfaceSignature]? = nil,
    nativePassThrough: Bool = false,
    systemListsGameController: Bool = false
  ) {
    self.serviceAddress = serviceAddress
    self.platformUniqueIdentifier = platformUniqueIdentifier
    self.vendorID = vendorID
    self.productID = productID
    self.deviceRelease = deviceRelease
    self.deviceClass = deviceClass
    self.deviceSubclass = deviceSubclass
    self.deviceProtocol = deviceProtocol
    self.configurationValue = configurationValue
    self.manufacturer = manufacturer
    self.productName = productName
    self.serialNumber = serialNumber
    self.transportProperty = transportProperty
    self.physicalLocationIdentifier = physicalLocationIdentifier
    self.stableParentDeviceIdentifier = stableParentDeviceIdentifier
    self.interfaces = interfaces
    self.nativePassThrough = nativePassThrough
    self.systemListsGameController = systemListsGameController
  }
}
