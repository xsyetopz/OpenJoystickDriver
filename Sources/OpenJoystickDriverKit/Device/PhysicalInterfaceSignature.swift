import CryptoKit
import Foundation

/// Transport/link kind; each interface signature distinguishes host-facing from
/// controller-side evidence.
///
/// The kebab-case `rawValue` is the spelling controller records use. Encoded output (reports,
/// `--json`, the endpoint) uses the lowerCamelCase `outputName`; decoding accepts only that.
public enum PhysicalTransport: String, CaseIterable, Codable, Equatable, Sendable {
  case usb
  case bluetoothClassic = "bluetooth-classic"
  case bluetoothLE = "bluetooth-le"
  case proprietaryRadioReceiver = "proprietary-radio-receiver"

  public var outputName: String {
    switch self {
    case .usb: "usb"
    case .bluetoothClassic: "bluetoothClassic"
    case .bluetoothLE: "bluetoothLE"
    case .proprietaryRadioReceiver: "proprietaryRadioReceiver"
    }
  }

  public init(from decoder: any Decoder) throws {
    let name = try decoder.singleValueContainer().decode(String.self)
    guard let transport = Self.allCases.first(where: { $0.outputName == name }) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Unknown transport: \(name)")
      )
    }
    self = transport
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(outputName)
  }
}

/// Access-backend vocabulary: IOKit HID, or raw USB through IOUSBHost or the DEXT.
public enum DeviceAccessBackend: String, Codable, Equatable, Sendable {
  case ioHID
  case ioUSBHost
  case usbDriverKit

  public init(route: USBTransportRoute) {
    switch route {
    case .ioUSBHost: self = .ioUSBHost
    case .usbDriverKit: self = .usbDriverKit
    }
  }
}

/// The required VID/PID pair after validating values reported by a HID API.
struct PhysicalHIDIdentity: Hashable, Sendable {
  let vendorID: UInt16
  let productID: UInt16

  init?(vendorID: UInt64?, productID: UInt64?) {
    guard let vendorID, let productID, let representableVendorID = UInt16(exactly: vendorID),
      let representableProductID = UInt16(exactly: productID)
    else { return nil }
    self.vendorID = representableVendorID
    self.productID = representableProductID
  }
}

public enum USBEndpointTransferType: String, Equatable, Sendable {
  case control
  case isochronous
  case bulk
  case interrupt
  case unknown
}

public enum USBEndpointDirection: String, Equatable, Sendable {
  case `in`
  case out
}

/// Available facts for one USB endpoint. Missing descriptor fields stay nil.
public struct PhysicalEndpointSignature: Equatable, Sendable {
  public let address: UInt8?
  public let direction: USBEndpointDirection?
  public let transferType: USBEndpointTransferType?
  public let maxPacketSize: UInt16?
  public let interval: UInt8?

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

/// A usage page and usage reported by the HID API. Each fact stays optional because
/// IOHID can expose a partial usage pair.
public struct HIDUsageSignature: Equatable, Sendable {
  public let usagePage: UInt32?
  public let usage: UInt32?

  public init(usagePage: UInt32? = nil, usage: UInt32? = nil) {
    self.usagePage = usagePage
    self.usage = usage
  }
}

public enum PhysicalHIDReportKind: String, Equatable, Sendable {
  case input
  case output
  case feature
}

/// Report identifiers and byte lengths exposed by a HID backend.
public struct PhysicalHIDReportSignature: Equatable, Sendable {
  public let kind: PhysicalHIDReportKind
  /// Nil means the backend did not expose identifiers. An empty array means it
  /// enumerated this report kind and found no numbered report IDs.
  public let reportIDs: [UInt32]?
  public let maximumLengthBytes: UInt32?

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
  /// Nil means the available API did not expose enough usage facts to decide.
  public let hasGamePadOrJoystickCollection: Bool?
  /// Nil means the backend could not enumerate elements.
  public let hasUsableElements: Bool?
  public let primaryUsage: HIDUsageSignature?
  public let collectionUsages: [HIDUsageSignature]?
  public let reportDescriptor: Data?
  public let reports: [PhysicalHIDReportSignature]?
  /// Lowercase SHA-256 of the reported descriptor bytes, when present.
  public let descriptorFingerprint: String?

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

  private static func fingerprint(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

/// Immutable facts available for one interface and alternate setting.
///
/// `hostTransport` describes the observed host-facing link. `physicalTransport`
/// is the controller-side link and remains nil unless evidence identifies it.
/// `usbRoute` preserves the actual OJD access path; `DeviceAccessBackend(route:)`
/// names its access backend.
public struct PhysicalInterfaceSignature: Equatable, Sendable {
  public let interfaceNumber: UInt8?
  public let alternateSetting: UInt8?
  public let interfaceClass: UInt8?
  public let interfaceSubclass: UInt8?
  public let interfaceProtocol: UInt8?
  public let configurationValue: UInt8?
  public let hostTransport: PhysicalTransport?
  public let physicalTransport: PhysicalTransport?
  public let accessBackend: DeviceAccessBackend?
  public let usbRoute: USBTransportRoute?
  public let endpoints: [PhysicalEndpointSignature]?
  public let hidLayout: HIDLayoutSummary?

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

/// One enumerated physical device with distinct, non-collapsed interface signatures.
public struct PhysicalDevice: Equatable, Sendable {
  public let serviceIdentity: USBTransportServiceIdentity?
  public let platformUniqueIdentifier: String?
  public let vendorID: UInt16?
  public let productID: UInt16?
  public let deviceRelease: UInt16?
  public let deviceClass: UInt8?
  public let deviceSubclass: UInt8?
  public let deviceProtocol: UInt8?
  public let configurationValue: UInt8?
  /// Manufacturer string returned by the active OS property API, if available.
  public let manufacturer: String?
  public let productName: String?
  public let serialNumber: String?
  /// Transport label returned by the active OS HID property API, if available.
  public let transportProperty: String?
  public let physicalLocationIdentifier: UInt32?
  public let stableParentDeviceIdentifier: String?
  public let interfaces: [PhysicalInterfaceSignature]?
  /// Whether the running macOS already exposes this device as a native gamepad
  /// (`GCController.supportsHIDDevice`). OJD leaves such a device to macOS before classification.
  public let nativePassThrough: Bool

  public init(
    serviceIdentity: USBTransportServiceIdentity? = nil,
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
    nativePassThrough: Bool = false
  ) {
    self.serviceIdentity = serviceIdentity
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
  }
}
