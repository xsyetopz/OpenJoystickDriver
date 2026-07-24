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

  /// True if this looks like our DriverKit virtual device.
  public let isOJDDriverKit: Bool
  /// True if this looks like our user-space IOHIDUserDevice.
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
    isOJDDriverKit: Bool,
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
    self.isOJDDriverKit = isOJDDriverKit
    self.isOJDUserSpace = isOJDUserSpace
    self.isGameControllerSupported = isGameControllerSupported
  }
}

/// Diagnostics snapshot returned by ``ApplicationServiceProtocol/getVirtualDeviceDiagnostics(reply:)``.
public struct ApplicationServiceVirtualDeviceDiagnosticsPayload: Codable, Sendable {
  public let userSpaceVirtualDeviceEnabled: Bool
  public let userSpaceVirtualDeviceStatus: String
  public let hidGamepads: [ApplicationServiceHIDGamepadSnapshot]
  /// DriverKit output injection stats using stable application-service payload keys.
  ///
  /// Present only when the application service is new enough to report it.
  public let driverKitOutputStats: ApplicationServiceDriverKitOutputStats?

  public init(
    userSpaceVirtualDeviceEnabled: Bool,
    userSpaceVirtualDeviceStatus: String,
    hidGamepads: [ApplicationServiceHIDGamepadSnapshot],
    driverKitOutputStats: ApplicationServiceDriverKitOutputStats? = nil
  ) {
    self.userSpaceVirtualDeviceEnabled = userSpaceVirtualDeviceEnabled
    self.userSpaceVirtualDeviceStatus = userSpaceVirtualDeviceStatus
    self.hidGamepads = hidGamepads
    self.driverKitOutputStats = driverKitOutputStats
  }
}

/// Stats for commands submitted through the SwifterKit DriverKit runtime.
public struct ApplicationServiceDriverKitOutputStats: Codable, Sendable {
  public let attempts: Int
  public let successes: Int
  public let failures: Int
  /// Stable payload key; SwifterKit command failures without a platform code report nil.
  public let lastErrorHex: String?
  public let connectionAttempts: Int
  public let connectionSuccesses: Int
  public let connectionFailures: Int
  public let lastConnectionErrorHex: String?
  public let lastDiscoverySummary: String?

  public init(
    attempts: Int,
    successes: Int,
    failures: Int,
    lastErrorHex: String?,
    connectionAttempts: Int = 0,
    connectionSuccesses: Int = 0,
    connectionFailures: Int = 0,
    lastConnectionErrorHex: String? = nil,
    lastDiscoverySummary: String? = nil
  ) {
    self.attempts = attempts
    self.successes = successes
    self.failures = failures
    self.lastErrorHex = lastErrorHex
    self.connectionAttempts = connectionAttempts
    self.connectionSuccesses = connectionSuccesses
    self.connectionFailures = connectionFailures
    self.lastConnectionErrorHex = lastConnectionErrorHex
    self.lastDiscoverySummary = lastDiscoverySummary
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
  public let driverKitValueEvents: Int
  public let driverKitReportEvents: Int
  public let userSpaceValueEvents: Int
  public let userSpaceReportEvents: Int
  public let userSpaceRequired: Bool
  public let userSpaceStatus: String
  /// Whether the signed host is entitled to open the DriverKit relay user client.
  public let driverKitRequired: Bool
  /// DriverKit-only self-test delta based on extension-side input delivery counters.
  public let driverKitInputReportDelta: Int?
  /// DriverKit-only self-test delta based on successful SwifterKit input submissions.
  public let driverKitSubmissionSuccessDelta: Int?
  /// Number of SwifterKit input submissions attempted during the self-test.
  public let driverKitSubmissionAttemptDelta: Int?
  /// Number of SwifterKit input submissions rejected during the self-test.
  public let driverKitSubmissionFailureDelta: Int?
  /// Stable payload key; nil when no platform error code is available.
  public let driverKitSubmissionLastErrorHex: String?
  public let driverKitConnectionAttemptDelta: Int?
  public let driverKitConnectionSuccessDelta: Int?
  public let driverKitConnectionFailureDelta: Int?
  public let driverKitLastConnectionErrorHex: String?
  public let driverKitDiscoverySummary: String?

  /// End-to-end DriverKit relay assessment.
  ///
  /// SwifterKit completes `submitHIDInputReport` only after native HID delivery, so a
  /// successful submission is authoritative even when callbacks or registry counters are absent.
  public var driverKitRelayVerdict: ApplicationServiceVirtualDeviceSelfTestVerdict {
    if let inputDelta = driverKitInputReportDelta, inputDelta > 0 { return .passed }
    if driverKitReportEvents > 0 || driverKitValueEvents > 0 { return .passed }
    guard driverKitRequired else { return .inconclusive }
    if driverKitInputReportDelta != nil { return .failed }

    let attempts = driverKitSubmissionAttemptDelta ?? 0
    guard attempts > 0 else { return .failed }
    let successes = driverKitSubmissionSuccessDelta ?? 0
    let failures = driverKitSubmissionFailureDelta ?? 0
    if successes == 0 || failures >= attempts { return .failed }
    return .passed
  }

  public var userSpaceVerdict: ApplicationServiceVirtualDeviceSelfTestVerdict {
    guard userSpaceRequired else { return .inconclusive }
    if userSpaceStatus.hasPrefix("error:") { return .failed }
    if userSpaceValueEvents > 0 || userSpaceReportEvents > 0 { return .passed }
    return .failed
  }

  /// True only when every required self-test assertion passed.
  public var isSuccessful: Bool {
    if driverKitRequired {
      return driverKitRelayVerdict == .passed && (!userSpaceRequired || userSpaceVerdict == .passed)
    }
    return userSpaceVerdict == .passed
  }

  public init(
    seconds: Int,
    driverKitValueEvents: Int,
    driverKitReportEvents: Int,
    userSpaceValueEvents: Int,
    userSpaceReportEvents: Int,
    userSpaceRequired: Bool = false,
    userSpaceStatus: String = "off",
    driverKitRequired: Bool = true,
    driverKitInputReportDelta: Int? = nil,
    driverKitSubmissionSuccessDelta: Int? = nil,
    driverKitSubmissionAttemptDelta: Int? = nil,
    driverKitSubmissionFailureDelta: Int? = nil,
    driverKitSubmissionLastErrorHex: String? = nil,
    driverKitConnectionAttemptDelta: Int? = nil,
    driverKitConnectionSuccessDelta: Int? = nil,
    driverKitConnectionFailureDelta: Int? = nil,
    driverKitLastConnectionErrorHex: String? = nil,
    driverKitDiscoverySummary: String? = nil
  ) {
    self.seconds = seconds
    self.driverKitValueEvents = driverKitValueEvents
    self.driverKitReportEvents = driverKitReportEvents
    self.userSpaceValueEvents = userSpaceValueEvents
    self.userSpaceReportEvents = userSpaceReportEvents
    self.userSpaceRequired = userSpaceRequired
    self.userSpaceStatus = userSpaceStatus
    self.driverKitRequired = driverKitRequired
    self.driverKitInputReportDelta = driverKitInputReportDelta
    self.driverKitSubmissionSuccessDelta = driverKitSubmissionSuccessDelta
    self.driverKitSubmissionAttemptDelta = driverKitSubmissionAttemptDelta
    self.driverKitSubmissionFailureDelta = driverKitSubmissionFailureDelta
    self.driverKitSubmissionLastErrorHex = driverKitSubmissionLastErrorHex
    self.driverKitConnectionAttemptDelta = driverKitConnectionAttemptDelta
    self.driverKitConnectionSuccessDelta = driverKitConnectionSuccessDelta
    self.driverKitConnectionFailureDelta = driverKitConnectionFailureDelta
    self.driverKitLastConnectionErrorHex = driverKitLastConnectionErrorHex
    self.driverKitDiscoverySummary = driverKitDiscoverySummary
  }

  private enum CodingKeys: String, CodingKey {
    case seconds
    case driverKitValueEvents
    case driverKitReportEvents
    case userSpaceValueEvents
    case userSpaceReportEvents
    case userSpaceRequired
    case userSpaceStatus
    case driverKitRequired
    case driverKitInputReportDelta
    case driverKitSubmissionSuccessDelta
    case driverKitSubmissionAttemptDelta
    case driverKitSubmissionFailureDelta
    case driverKitSubmissionLastErrorHex
    case driverKitConnectionAttemptDelta
    case driverKitConnectionSuccessDelta
    case driverKitConnectionFailureDelta
    case driverKitLastConnectionErrorHex
    case driverKitDiscoverySummary
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      seconds: try values.decode(Int.self, forKey: .seconds),
      driverKitValueEvents: try values.decode(Int.self, forKey: .driverKitValueEvents),
      driverKitReportEvents: try values.decode(Int.self, forKey: .driverKitReportEvents),
      userSpaceValueEvents: try values.decode(Int.self, forKey: .userSpaceValueEvents),
      userSpaceReportEvents: try values.decode(Int.self, forKey: .userSpaceReportEvents),
      userSpaceRequired: try values.decode(Bool.self, forKey: .userSpaceRequired),
      userSpaceStatus: try values.decode(String.self, forKey: .userSpaceStatus),
      driverKitRequired: try values.decode(Bool.self, forKey: .driverKitRequired),
      driverKitInputReportDelta: try values.decodeIfPresent(
        Int.self,
        forKey: .driverKitInputReportDelta
      ),
      driverKitSubmissionSuccessDelta: try values.decodeIfPresent(
        Int.self,
        forKey: .driverKitSubmissionSuccessDelta
      ),
      driverKitSubmissionAttemptDelta: try values.decodeIfPresent(
        Int.self,
        forKey: .driverKitSubmissionAttemptDelta
      ),
      driverKitSubmissionFailureDelta: try values.decodeIfPresent(
        Int.self,
        forKey: .driverKitSubmissionFailureDelta
      ),
      driverKitSubmissionLastErrorHex: try values.decodeIfPresent(
        String.self,
        forKey: .driverKitSubmissionLastErrorHex
      ),
      driverKitConnectionAttemptDelta: try values.decodeIfPresent(
        Int.self,
        forKey: .driverKitConnectionAttemptDelta
      ),
      driverKitConnectionSuccessDelta: try values.decodeIfPresent(
        Int.self,
        forKey: .driverKitConnectionSuccessDelta
      ),
      driverKitConnectionFailureDelta: try values.decodeIfPresent(
        Int.self,
        forKey: .driverKitConnectionFailureDelta
      ),
      driverKitLastConnectionErrorHex: try values.decodeIfPresent(
        String.self,
        forKey: .driverKitLastConnectionErrorHex
      ),
      driverKitDiscoverySummary: try values.decodeIfPresent(
        String.self,
        forKey: .driverKitDiscoverySummary
      )
    )
  }
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
  /// USB serial number, or nil if not reported.
  public let serialNumber: String?
  /// Source-backed protocol variant selected from the generated controller record.
  public let protocolVariant: ControllerProtocolVariant
  /// Source-backed mapping quirks from the controller record.
  public let mappingFlags: [String]
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
    case serialNumber
    case protocolVariant
    case mappingFlags
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
    serialNumber: String?,
    protocolVariant: ControllerProtocolVariant = .unknown,
    mappingFlags: [String] = [],
    inputEndpoint: UInt8 = 0,
    outputEndpoint: UInt8 = 0,
    needsSetConfiguration: Bool = false,
    postHandshakeSettleMs: Int = 0,
    preferredBackends: [String] = [],
    physicalOutputCapabilities: PhysicalControllerOutputCapabilities = .none,
    runtimeIdentifier: String? = nil
  ) {
    self.runtimeIdentifier = runtimeIdentifier
      ?? String(format: "%04X:%04X:M", vendorID, productID)
    self.name = name
    self.vendorID = vendorID
    self.productID = productID
    self.parser = parser
    self.connection = connection
    self.serialNumber = serialNumber
    self.protocolVariant = protocolVariant
    self.mappingFlags = mappingFlags
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
    self.serialNumber = try container.decodeIfPresent(String.self, forKey: .serialNumber)
    self.protocolVariant = try container.decode(
      ControllerProtocolVariant.self,
      forKey: .protocolVariant
    )
    self.mappingFlags = try container.decodeIfPresent([String].self, forKey: .mappingFlags) ?? []
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

  /// Creates a new ApplicationServiceStatusPayload.
  public init(
    inputMonitoring: String,
    accessibility: String,
    connectedDevices: [ApplicationServiceDeviceDescription],
    userSpaceVirtualDeviceEnabled: Bool? = nil,
    userSpaceVirtualDeviceStatus: String? = nil,
    compatibilityIdentity: String? = nil
  ) {
    self.inputMonitoring = inputMonitoring
    self.accessibility = accessibility
    self.connectedDevices = connectedDevices
    self.userSpaceVirtualDeviceEnabled = userSpaceVirtualDeviceEnabled
    self.userSpaceVirtualDeviceStatus = userSpaceVirtualDeviceStatus
    self.compatibilityIdentity = compatibilityIdentity
  }
}
