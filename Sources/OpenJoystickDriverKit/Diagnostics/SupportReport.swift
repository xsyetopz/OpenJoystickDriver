import Foundation

public enum GameControllerProbeConfiguration {
  public static let defaultSeconds = 5
  public static let minimumSeconds = 1
  public static let maximumSeconds = 60

  public static func boundedSeconds(_ value: Int) -> Int {
    min(max(value, minimumSeconds), maximumSeconds)
  }
}

/// A user-reviewable, machine-readable snapshot for controller support requests.
///
/// Raw serial values, filesystem paths, packet payloads, HID location IDs, and
/// free-form DriverKit discovery text are intentionally not represented.
public struct SupportReport: Codable, Sendable {
  public static let supportDiagnosticType = "com.openjoystickdriver.support.diagnostic"
  public static let source = "urn:openjoystickdriver:support"
  public static let dataSchema =
    "https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/Resources/Schemas/"
    + "report.schema.json#/$defs/supportDiagnosticData"

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

  public struct Configuration: Codable, Sendable { public let userSpaceVirtualDeviceEnabled: Bool? }

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
    public let isOJDUserSpace: Bool
    public let isGameControllerSupported: Bool?
  }

  public struct Payload: Codable, Sendable {
    public let privacy: Privacy
    public let system: System
    public let permissions: Permissions
    public let applicationService: ApplicationService
    public let configuration: Configuration
    public let controllers: [Controller]
    public let hidGamepads: [HIDGamepad]
    public let appleGameControllerAudit: AppleGameControllerSupportAudit?
    public let notes: [String]
  }

  public let specversion: String
  public let id: String
  public let source: String
  public let type: String
  public let time: String
  public let datacontenttype: String
  public let dataschema: String
  public let data: Payload

  private enum CodingKeys: String, CodingKey {
    case specversion, id, source, type, time, datacontenttype, dataschema, data
  }

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
    let generatedAtString = ISO8601DateFormatter().string(from: generatedAt)
    specversion = "1.0"
    id = UUID().uuidString
    self.source = Self.source
    type = Self.supportDiagnosticType
    time = generatedAtString
    datacontenttype = "application/json"
    dataschema = Self.dataSchema
    let privacy = Privacy(
      includesRawSerialNumbers: false,
      includesFilesystemPaths: false,
      includesPacketPayloads: false,
      includesHIDLocationIDs: false,
      includesDeviceProductNames: true
    )
    let system = System(
      appVersion: appVersion,
      macOSVersion: macOSVersion,
      architecture: architecture
    )
    let permissions = Permissions(
      inputMonitoring: inputMonitoring.description,
      accessibility: status?.accessibility ?? "unknown"
    )
    let applicationService = ApplicationService(
      installed: applicationServiceInstalled,
      connected: applicationServiceConnected,
      runtimeState: applicationServiceHealth?.state,
      activeCount: applicationServiceHealth?.activeCount
    )
    let configuration = Configuration(
      userSpaceVirtualDeviceEnabled: status?.userSpaceVirtualDeviceEnabled
    )
    let controllers = (status?.connectedDevices ?? []).map {
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
    let hidGamepads = (virtualDiagnostics?.hidGamepads ?? []).map {
      HIDGamepad(
        vendorID: $0.vendorID,
        productID: $0.productID,
        product: $0.product,
        transport: $0.transport,
        serialKind: $0.serialKind,
        ioUserClass: $0.ioUserClass,
        isOJDUserSpace: $0.isOJDUserSpace,
        isGameControllerSupported: $0.isGameControllerSupported
      )
    }.sorted {
      if $0.vendorID != $1.vendorID { return $0.vendorID < $1.vendorID }
      if $0.productID != $1.productID { return $0.productID < $1.productID }
      return ($0.product ?? "") < ($1.product ?? "")
    }
    var reportNotes = [
      "Review this file before sharing. Device product names are included.",
      "Serial values, paths, packet payloads, HID locations, and discovery text are excluded."
    ]
    if status == nil { reportNotes.append("Application service status was unavailable.") }
    if virtualDiagnostics == nil {
      reportNotes.append("Virtual-device diagnostics were unavailable.")
    }
    if appleGameControllerAudit == nil {
      reportNotes.append("Apple GameController catalog audit was unavailable.")
    }
    data = Payload(
      privacy: privacy,
      system: system,
      permissions: permissions,
      applicationService: applicationService,
      configuration: configuration,
      controllers: controllers,
      hidGamepads: hidGamepads,
      appleGameControllerAudit: appleGameControllerAudit,
      notes: reportNotes
    )
  }

  /// Encodes the report as stable, reviewable CloudEvents structured JSON.
  public func encodedJSON() throws -> Foundation.Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(self)
  }
}
