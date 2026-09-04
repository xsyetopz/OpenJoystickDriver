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

/// Diagnostics snapshot returned by ``ApplicationServiceProtocol/getVirtualDeviceDiagnostics(reply:)``.
public struct ApplicationServiceVirtualDeviceDiagnosticsPayload: Codable, Sendable {
  public let userSpaceVirtualDeviceEnabled: Bool
  public let userSpaceVirtualDeviceStatus: String
  public let hidGamepads: [ApplicationServiceHIDGamepadSnapshot]

  public init(
    userSpaceVirtualDeviceEnabled: Bool,
    userSpaceVirtualDeviceStatus: String,
    hidGamepads: [ApplicationServiceHIDGamepadSnapshot]
  ) {
    self.userSpaceVirtualDeviceEnabled = userSpaceVirtualDeviceEnabled
    self.userSpaceVirtualDeviceStatus = userSpaceVirtualDeviceStatus
    self.hidGamepads = hidGamepads
  }
}

/// End-to-end verdict for one virtual-device self-test path.
public enum ApplicationServiceVirtualDeviceSelfTestVerdict: String, Codable, Sendable {
  case passed
  case failed
  case inconclusive
}

/// Result of a short "press buttons now" self-test for virtual device input delivery.
public struct ApplicationServiceVirtualDeviceSelfTestPayload: Codable, Sendable {
  public let seconds: Int
  public let userSpaceValueEvents: Int
  public let userSpaceReportEvents: Int
  public let userSpaceRequired: Bool
  public let userSpaceStatus: String

  public var userSpaceVerdict: ApplicationServiceVirtualDeviceSelfTestVerdict {
    guard userSpaceRequired else { return .inconclusive }
    if userSpaceStatus.hasPrefix("error:") { return .failed }
    if userSpaceValueEvents > 0 || userSpaceReportEvents > 0 { return .passed }
    return .failed
  }

  public var isSuccessful: Bool { userSpaceVerdict == .passed }

  public init(
    seconds: Int,
    userSpaceValueEvents: Int,
    userSpaceReportEvents: Int,
    userSpaceRequired: Bool = true,
    userSpaceStatus: String = "off"
  ) {
    self.seconds = seconds
    self.userSpaceValueEvents = userSpaceValueEvents
    self.userSpaceReportEvents = userSpaceReportEvents
    self.userSpaceRequired = userSpaceRequired
    self.userSpaceStatus = userSpaceStatus
  }
}

/// Discovery route that owns a connected controller pipeline.
public enum ApplicationServiceDeviceDiscoverySource: String, Codable, Sendable {
  case hid
  case rawUSB = "raw-usb"
  case unknown
}

/// Structured description of a connected controller, used in ``ApplicationServiceStatusPayload``.
public struct ApplicationServiceDeviceDescription: Codable, Sendable {
  /// Opaque selector for one connected controller during the current runtime session.
  public let runtimeIdentifier: String
  /// Human-readable controller name.
  public let name: String
  /// USB vendor ID.
  public let vendorID: UInt16
  /// USB product ID.
  public let productID: UInt16
  /// Name of the protocol parser in use (e.g. "GIP", "DS4").
  public let parser: String
  /// Connection type (e.g. "USB", "HID").
  public let connection: String
  /// Discovery route that owns the live controller pipeline.
  public let discoverySource: ApplicationServiceDeviceDiscoverySource
  /// Observed physical ownership route used by virtual exposure policy.
  public let physicalOwnership: ControllerOwnershipObservation
  /// Duplicate-device risk implied by the current physical ownership observation.
  public let duplicateExposureRisk: DuplicateExposureRisk
  /// USB serial number, or nil if not reported.
  public let serialNumber: String?
  /// Source-backed protocol variant selected from the generated controller record.
  public let protocolVariant: ControllerProtocolVariant
  /// Source-backed mapping quirks from the controller record.
  public let quirks: [String]
  /// Interrupt IN endpoint address used by USB transports.
  public let inputEndpoint: UInt8
  /// Interrupt OUT endpoint address used by USB transports.
  public let outputEndpoint: UInt8
  /// Whether the USB pipeline calls setConfiguration(1) before claiming.
  public let needsSetConfiguration: Bool
  /// Post-handshake settle delay in milliseconds.
  public let postHandshakeSettleMs: Int
  /// Preferred virtual output backends from the controller record.
  public let preferredBackends: [String]
  /// Exact source-backed motors and lighting features of the active parser.
  public let physicalOutputCapabilities: PhysicalControllerOutputCapabilities

  private enum CodingKeys: String, CodingKey {
    case name
    case runtimeIdentifier
    case vendorID
    case productID
    case parser
    case connection
    case discoverySource
    case physicalOwnership
    case duplicateExposureRisk
    case serialNumber
    case protocolVariant
    case quirks
    case inputEndpoint
    case outputEndpoint
    case needsSetConfiguration
    case postHandshakeSettleMs
    case preferredBackends
    case physicalOutputCapabilities
  }

  /// Creates a new ApplicationServiceDeviceDescription.
  public init(
    name: String,
    vendorID: UInt16,
    productID: UInt16,
    parser: String,
    connection: String,
    discoverySource: ApplicationServiceDeviceDiscoverySource = .unknown,
    physicalOwnership: ControllerOwnershipObservation = .unknown,
    duplicateExposureRisk: DuplicateExposureRisk = .unknownOwnership,
    serialNumber: String?,
    protocolVariant: ControllerProtocolVariant = .unknown,
    quirks: [String] = [],
    inputEndpoint: UInt8 = 0,
    outputEndpoint: UInt8 = 0,
    needsSetConfiguration: Bool = false,
    postHandshakeSettleMs: Int = 0,
    preferredBackends: [String] = [],
    physicalOutputCapabilities: PhysicalControllerOutputCapabilities = .none,
    runtimeIdentifier: String? = nil
  ) {
    self.runtimeIdentifier = runtimeIdentifier ?? String(format: "%04X:%04X:M", vendorID, productID)
    self.name = name
    self.vendorID = vendorID
    self.productID = productID
    self.parser = parser
    self.connection = connection
    self.discoverySource = discoverySource
    self.physicalOwnership = physicalOwnership
    self.duplicateExposureRisk = duplicateExposureRisk
    self.serialNumber = serialNumber
    self.protocolVariant = protocolVariant
    self.quirks = quirks
    self.inputEndpoint = inputEndpoint
    self.outputEndpoint = outputEndpoint
    self.needsSetConfiguration = needsSetConfiguration
    self.postHandshakeSettleMs = postHandshakeSettleMs
    self.preferredBackends = preferredBackends
    self.physicalOutputCapabilities = physicalOutputCapabilities
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.runtimeIdentifier = try container.decode(String.self, forKey: .runtimeIdentifier)
    self.name = try container.decode(String.self, forKey: .name)
    self.vendorID = try container.decode(UInt16.self, forKey: .vendorID)
    self.productID = try container.decode(UInt16.self, forKey: .productID)
    self.parser = try container.decode(String.self, forKey: .parser)
    self.connection = try container.decode(String.self, forKey: .connection)
    self.discoverySource = try container.decode(
      ApplicationServiceDeviceDiscoverySource.self,
      forKey: .discoverySource
    )
    self.physicalOwnership =
      try container.decodeIfPresent(ControllerOwnershipObservation.self, forKey: .physicalOwnership)
      ?? .unknown
    self.duplicateExposureRisk =
      try container.decodeIfPresent(DuplicateExposureRisk.self, forKey: .duplicateExposureRisk)
      ?? .unknownOwnership
    self.serialNumber = try container.decodeIfPresent(String.self, forKey: .serialNumber)
    self.protocolVariant = try container.decode(
      ControllerProtocolVariant.self,
      forKey: .protocolVariant
    )
    self.quirks = try container.decodeIfPresent([String].self, forKey: .quirks) ?? []
    self.inputEndpoint = try container.decodeIfPresent(UInt8.self, forKey: .inputEndpoint) ?? 0
    self.outputEndpoint = try container.decodeIfPresent(UInt8.self, forKey: .outputEndpoint) ?? 0
    self.needsSetConfiguration =
      try container.decodeIfPresent(Bool.self, forKey: .needsSetConfiguration) ?? false
    self.postHandshakeSettleMs =
      try container.decodeIfPresent(Int.self, forKey: .postHandshakeSettleMs) ?? 0
    self.preferredBackends =
      try container.decodeIfPresent([String].self, forKey: .preferredBackends) ?? []
    self.physicalOutputCapabilities = try container.decode(
      PhysicalControllerOutputCapabilities.self,
      forKey: .physicalOutputCapabilities
    )
  }
}

/// Status snapshot returned by ``ApplicationServiceProtocol/getStatus(reply:)``.
///
/// Contains the current macOS permission states (as human-readable strings like
/// "granted" or "denied") and descriptions of all connected controllers.
public struct ApplicationServiceCompatibilityRetryPayload: Codable, Sendable, Equatable {
  public let requestedIdentity: String
  public let priorProfileIdentity: String
  public let phase: String

  public init(requestedIdentity: String, priorProfileIdentity: String, phase: String) {
    self.requestedIdentity = requestedIdentity
    self.priorProfileIdentity = priorProfileIdentity
    self.phase = phase
  }
}

public struct ApplicationServiceStatusPayload: Codable, Sendable {
  /// Input Monitoring permission state (e.g. "granted", "denied").
  public let inputMonitoring: String
  /// Accessibility permission used to publish an IOHIDUserDevice.
  public let accessibility: String
  /// Structured descriptions of all connected controllers.
  public let connectedDevices: [ApplicationServiceDeviceDescription]
  /// Whether the user-space virtual gamepad is enabled (IOHIDUserDevice).
  public let userSpaceVirtualDeviceEnabled: Bool?
  /// Short status string for the user-space virtual gamepad (e.g. "on", "off", "error: ...").
  public let userSpaceVirtualDeviceStatus: String?
  /// Compatibility mode identity/protocol selection.
  public let compatibilityIdentity: String?
  /// Identity currently published by the live compatibility backend, if any.
  public let compatibilityLiveIdentity: String?
  /// Persisted transition context available for an explicit retry after rollback failure.
  public let compatibilityRetry: ApplicationServiceCompatibilityRetryPayload?

  /// Creates a new ApplicationServiceStatusPayload.
  public init(
    inputMonitoring: String,
    accessibility: String,
    connectedDevices: [ApplicationServiceDeviceDescription],
    userSpaceVirtualDeviceEnabled: Bool? = nil,
    userSpaceVirtualDeviceStatus: String? = nil,
    compatibilityIdentity: String? = nil,
    compatibilityLiveIdentity: String? = nil,
    compatibilityRetry: ApplicationServiceCompatibilityRetryPayload? = nil
  ) {
    self.inputMonitoring = inputMonitoring
    self.accessibility = accessibility
    self.connectedDevices = connectedDevices
    self.userSpaceVirtualDeviceEnabled = userSpaceVirtualDeviceEnabled
    self.userSpaceVirtualDeviceStatus = userSpaceVirtualDeviceStatus
    self.compatibilityIdentity = compatibilityIdentity
    self.compatibilityLiveIdentity = compatibilityLiveIdentity
    self.compatibilityRetry = compatibilityRetry
  }
}
