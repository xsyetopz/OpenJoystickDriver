import Foundation

/// A user-reviewable, machine-readable snapshot for controller support requests.
///
/// Raw serial values, filesystem paths, packet payloads, HID location IDs, and
/// free-form DriverKit discovery text are intentionally not represented.
public struct SupportReport: Codable, Sendable {
  /// Increment when the report's encoded contract changes incompatibly.
  public static let currentSchemaVersion = 4

  public struct Privacy: Codable, Sendable {
    public let includesRawSerialNumbers: Bool
    public let includesFilesystemPaths: Bool
    public let includesPacketPayloads: Bool
    public let includesHIDLocationIDs: Bool
    public let includesDeviceProductNames: Bool
  }

  public struct System: Codable, Sendable {
    public let appVersion: String
    public let macOSVersion: String
    public let architecture: String
  }

  public struct Permissions: Codable, Sendable {
    public let inputMonitoring: String
    public let accessibility: String
  }

  public struct ApplicationService: Codable, Sendable {
    public let installed: Bool
    public let connected: Bool
    public let runtimeState: String?
    public let activeCount: Int?
  }

  public struct Configuration: Codable, Sendable {
    public let compatibilityIdentity: String?
    public let userSpaceVirtualDeviceEnabled: Bool?
  }

  public struct Controller: Codable, Sendable {
    public let name: String
    public let vendorID: UInt16
    public let productID: UInt16
    public let parser: String
    public let connection: String
    public let serialNumberPresent: Bool
    public let protocolVariant: String
    public let mappingFlags: [String]
    public let inputEndpoint: UInt8
    public let outputEndpoint: UInt8
    public let needsSetConfiguration: Bool
    public let postHandshakeSettleMs: Int
    public let preferredBackends: [String]
    public let physicalOutputCapabilities: PhysicalControllerOutputCapabilities
  }

  public struct HIDGamepad: Codable, Sendable {
    public let vendorID: UInt16
    public let productID: UInt16
    public let product: String?
    public let transport: String?
    public let serialKind: ApplicationServiceSerialKind
    public let ioUserClass: String?
    public let isOJDDriverKit: Bool
    public let isOJDUserSpace: Bool
    public let isGameControllerSupported: Bool?
  }

  public struct DriverKitOutput: Codable, Sendable {
    public let attempts: Int
    public let successes: Int
    public let failures: Int
    public let lastErrorHex: String?
    public let connectionAttempts: Int
    public let connectionSuccesses: Int
    public let connectionFailures: Int
    public let lastConnectionErrorHex: String?
  }

  public let schemaVersion: Int
  public let generatedAt: String
  public let privacy: Privacy
  public let system: System
  public let permissions: Permissions
  public let applicationService: ApplicationService
  public let configuration: Configuration
  public let controllers: [Controller]
  public let outputValidationPlans: [PhysicalOutputValidationPlan]
  public let hidGamepads: [HIDGamepad]
  public let driverKitOutput: DriverKitOutput?
  public let appleGameControllerAudit: AppleGameControllerSupportAudit?
  public let notes: [String]

  /// Creates a redacted report from application service and local diagnostic snapshots.
  public init(
    generatedAt: Date,
    appVersion: String,
    macOSVersion: String,
    architecture: String,
    inputMonitoring: PermissionManager.AccessState,
    applicationServiceInstalled: Bool,
    applicationServiceConnected: Bool,
    applicationServiceHealth: ApplicationServiceManager.ApplicationServiceHealth?,
    appleGameControllerAudit: AppleGameControllerSupportAudit? = nil,
    status: ApplicationServiceStatusPayload?,
    virtualDiagnostics: ApplicationServiceVirtualDeviceDiagnosticsPayload?
  ) {
    schemaVersion = Self.currentSchemaVersion
    self.generatedAt = ISO8601DateFormatter().string(from: generatedAt)
    privacy = Privacy(
      includesRawSerialNumbers: false,
      includesFilesystemPaths: false,
      includesPacketPayloads: false,
      includesHIDLocationIDs: false,
      includesDeviceProductNames: true
    )
    system = System(
      appVersion: appVersion,
      macOSVersion: macOSVersion,
      architecture: architecture
    )
    permissions = Permissions(
      inputMonitoring: inputMonitoring.description,
      accessibility: status?.accessibility ?? "unknown"
    )
    applicationService = ApplicationService(
      installed: applicationServiceInstalled,
      connected: applicationServiceConnected,
      runtimeState: applicationServiceHealth?.state,
      activeCount: applicationServiceHealth?.activeCount
    )
    self.appleGameControllerAudit = appleGameControllerAudit
    configuration = Configuration(
      compatibilityIdentity: status?.compatibilityIdentity,
      userSpaceVirtualDeviceEnabled: status?.userSpaceVirtualDeviceEnabled
    )
    controllers = (status?.connectedDevices ?? []).map {
      Controller(
        name: $0.name,
        vendorID: $0.vendorID,
        productID: $0.productID,
        parser: $0.parser,
        connection: $0.connection,
        serialNumberPresent: $0.serialNumber?.isEmpty == false,
        protocolVariant: $0.protocolVariant.rawValue,
        mappingFlags: $0.mappingFlags.sorted(),
        inputEndpoint: $0.inputEndpoint,
        outputEndpoint: $0.outputEndpoint,
        needsSetConfiguration: $0.needsSetConfiguration,
        postHandshakeSettleMs: $0.postHandshakeSettleMs,
        preferredBackends: $0.preferredBackends.sorted(),
        physicalOutputCapabilities: $0.physicalOutputCapabilities
      )
    }.sorted {
      if $0.vendorID != $1.vendorID { return $0.vendorID < $1.vendorID }
      if $0.productID != $1.productID { return $0.productID < $1.productID }
      return $0.name < $1.name
    }
    outputValidationPlans = (status?.connectedDevices ?? [])
      .map(PhysicalOutputValidationPlan.init(device:))
      .filter { !$0.steps.isEmpty }
      .sorted {
        if $0.vendorID != $1.vendorID { return $0.vendorID < $1.vendorID }
        return $0.productID < $1.productID
      }
    hidGamepads = (virtualDiagnostics?.hidGamepads ?? []).map {
      HIDGamepad(
        vendorID: $0.vendorID,
        productID: $0.productID,
        product: $0.product,
        transport: $0.transport,
        serialKind: $0.serialKind,
        ioUserClass: $0.ioUserClass,
        isOJDDriverKit: $0.isOJDDriverKit,
        isOJDUserSpace: $0.isOJDUserSpace,
        isGameControllerSupported: $0.isGameControllerSupported
      )
    }.sorted {
      if $0.vendorID != $1.vendorID { return $0.vendorID < $1.vendorID }
      if $0.productID != $1.productID { return $0.productID < $1.productID }
      return ($0.product ?? "") < ($1.product ?? "")
    }
    if let stats = virtualDiagnostics?.driverKitOutputStats {
      driverKitOutput = DriverKitOutput(
        attempts: stats.attempts,
        successes: stats.successes,
        failures: stats.failures,
        lastErrorHex: stats.lastErrorHex,
        connectionAttempts: stats.connectionAttempts,
        connectionSuccesses: stats.connectionSuccesses,
        connectionFailures: stats.connectionFailures,
        lastConnectionErrorHex: stats.lastConnectionErrorHex
      )
    } else {
      driverKitOutput = nil
    }

    var reportNotes = [
      "Review this file before sharing. Device product names are included.",
      "Serial values, paths, packet payloads, HID locations, and discovery text are excluded.",
    ]
    if status == nil { reportNotes.append("Application service status was unavailable.") }
    if virtualDiagnostics == nil {
      reportNotes.append("Virtual-device diagnostics were unavailable.")
    }
    if appleGameControllerAudit == nil {
      reportNotes.append("Apple GameController catalog audit was unavailable.")
    }
    notes = reportNotes
  }

  /// Encodes the report as stable, reviewable JSON.
  public func encodedJSON() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(self)
  }
}
