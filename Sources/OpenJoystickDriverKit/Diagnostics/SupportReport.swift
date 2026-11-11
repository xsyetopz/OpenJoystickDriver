import Foundation

/// The time limits of the GameController probe tool.
public enum GameControllerProbeConfiguration {
  /// The seconds the probe runs unless the caller sets a time.
  public static let defaultSeconds = 5
  /// The least seconds the probe runs.
  public static let minimumSeconds = 1
  /// The most seconds the probe runs.
  public static let maximumSeconds = 60

  /// `value` limited to ``minimumSeconds`` through ``maximumSeconds``.
  public static func boundedSeconds(_ value: Int) -> Int {
    min(max(value, minimumSeconds), maximumSeconds)
  }
}

/// A user-reviewable, machine-readable snapshot for controller support requests.
///
/// Raw serial values, filesystem paths, packet payloads, HID location IDs, and
/// free-form DriverKit discovery text are intentionally not represented.
public struct SupportReport: Codable, Sendable {
  /// The CloudEvents `type` of a support report.
  public static let supportDiagnosticType = "com.openjoystickdriver.support.diagnostic"
  /// The CloudEvents `source` of a support report.
  public static let source = "urn:openjoystickdriver:support"
  /// The URL of the JSON Schema that describes ``data``.
  public static let dataSchema =
    OpenJoystickDriverAPI.schemaBase + "report.schema.json#/$defs/supportDiagnosticData"

  /// What the report leaves out and what it keeps.
  public struct Privacy: Codable, Sendable {
    /// Whether the report holds raw serial numbers.
    public let includesRawSerialNumbers: Bool
    /// Whether the report holds filesystem paths.
    public let includesFilesystemPaths: Bool
    /// Whether the report holds packet payloads.
    public let includesPacketPayloads: Bool
    /// Whether the report holds HID location IDs.
    public let includesHIDLocationIDs: Bool
    /// Whether the report holds the product names of devices; it does.
    public let includesDeviceProductNames: Bool
  }

  /// The build and the operating system that produced the report.
  public struct System: Codable, Sendable {
    /// The identity of the OJD build.
    public let buildIdentity: BuildIdentity
    /// The operating system name, such as `macOS`.
    public let osName: String
    /// The operating system version as major, minor and patch numbers.
    public let osVersion: String
    /// The processor architecture, such as `arm64`.
    public let architecture: String

    /// The keys of the JSON encoding.
    private enum CodingKeys: String, CodingKey {
      /// The `buildIdentity` key.
      case buildIdentity
      /// The `osName` key.
      case osName
      /// The `osVersion` key.
      case osVersion
      /// The `architecture` key.
      case architecture
    }
  }

  /// The state of the permissions that OJD needs.
  public struct Permissions: Codable, Sendable {
    /// Whether macOS lets OJD read input.
    public let inputRead: PermissionManager.AccessState
    /// Whether macOS lets OJD post events; `unknown` when the service did not answer.
    public let inputInject: PermissionManager.AccessState
  }

  /// What the report knows about the OJD service process.
  public struct ApplicationService: Codable, Sendable {
    /// Whether the main app has a login-item registration.
    public let installed: Bool
    /// Whether the app is connected to the service.
    public let connected: Bool
    /// `running` when the main app's local server answers, otherwise `not running`; nil when
    /// unknown.
    public let runtimeState: String?
    /// 1 when the main app's local server answers, otherwise 0; nil when unknown.
    public let activeCount: Int?
  }

  /// The settings that shape what the service does.
  public struct Configuration: Codable, Sendable {
    /// Whether the user-space virtual gamepad is enabled.
    public let userSpaceVirtualDeviceEnabled: Bool?
  }

  /// A connected controller that a protocol driver is bound to.
  public struct Controller: Codable, Sendable {
    /// The controller's name.
    public let name: String
    /// The USB vendor ID.
    public let vendorID: UInt16
    /// The USB product ID.
    public let productID: UInt16
    /// The bound protocol family and resolved variant, such as `XboxGIP:USB`.
    public let protocolBinding: String
    /// The connection type, such as USB or Bluetooth.
    public let connection: String
    /// Whether the controller reports a serial number; the number itself is not in the report.
    public let serialNumberPresent: Bool
    /// The typed protocol parameters of the controller record, as sorted `name=value` entries.
    public let parameters: [String]
    /// The structured, redacted decision that bound the controller.
    public let binding: ProtocolBindingResult
    /// The interrupt IN endpoint address that USB transports use.
    public let inputEndpoint: UInt8
    /// The interrupt OUT endpoint address that USB transports use.
    public let outputEndpoint: UInt8
    /// Whether the USB pipeline sets configuration 1 before it claims the controller.
    public let needsSetConfiguration: Bool
    /// The settle delay after the handshake, in milliseconds.
    public let postHandshakeSettleMilliseconds: Int
    /// The virtual output backends that the controller record prefers, sorted.
    public let preferredBackends: [String]
    /// The motors and lighting features that the active parser supports.
    public let physicalOutputCapabilities: PhysicalControllerOutputCapabilities
    /// The connection state of the controller; nil when the service reports none.
    public let connectionState: ControllerConnectionState?
    /// The state of the controller's session.
    public let sessionState: ControllerSessionState
    /// The result of the latest required startup command sequence; nil when none ran.
    public let startupCommandStatus: String?
    /// How healthy the controller's input is.
    public let inputHealth: ControllerInputHealth
  }

  /// An observed device that no protocol driver bound.
  public struct UnboundDevice: Codable, Sendable {
    /// The USB vendor ID.
    public let vendorID: UInt16
    /// The USB product ID.
    public let productID: UInt16
    /// The connection type, such as USB or Bluetooth.
    public let connection: String
    /// The structured, redacted decision that left the device unbound.
    public let binding: ProtocolBindingResult
  }

  /// A game controller that macOS exposes through HID.
  public struct HIDGamepad: Codable, Sendable {
    /// The USB vendor ID.
    public let vendorID: UInt16
    /// The USB product ID.
    public let productID: UInt16
    /// The product name; nil when the device reports none.
    public let product: String?
    /// The transport, such as USB; nil when the device reports none.
    public let transport: String?
    /// The redacted serial number state of the device.
    public let serialKind: ApplicationServiceSerialKind
    /// The IOKit class of the device's user client; nil when the device reports none.
    public let ioUserClass: String?
    /// Whether the device looks like a virtual HID device that the OJD app owns.
    public let isOJDUserSpace: Bool
    /// Whether the GameController framework gives the device a controller; nil when not checked.
    public let isGameControllerSupported: Bool?
  }

  /// The report's content.
  public struct Payload: Codable, Sendable {
    /// The version of the OJD API.
    public let apiVersion: String
    /// The kind of document, `SupportDiagnostic`.
    public let kind: String
    /// What the report leaves out.
    public let privacy: Privacy
    /// The build and operating system.
    public let system: System
    /// The permission states.
    public let permissions: Permissions
    /// The service's state.
    public let applicationService: ApplicationService
    /// The settings that shape the service.
    public let configuration: Configuration
    /// The connected controllers, sorted by vendor ID, product ID and name.
    public let controllers: [Controller]
    /// The devices that no protocol driver bound.
    public let unboundDevices: [UnboundDevice]
    /// The game controllers that macOS exposes through HID, sorted by vendor ID, product ID and
    /// product name.
    public let hidGamepads: [HIDGamepad]
    /// The audit of the system's game controller catalog; nil when it was not available.
    public let systemGamepadAudit: SystemGamepadSupportAudit?
    /// The newest frames of each connected controller with the five per-stage stamps, empty when
    /// the service was stopped or had no frames.
    public let frameTimings: [ControllerFrameTimings]
    /// The notes to read before sharing the report.
    public let notes: [String]
  }

  /// The CloudEvents version, `1.0`.
  public let specversion: String
  /// The unique ID of the report.
  public let id: String
  /// The CloudEvents source, `source`.
  public let source: String
  /// The CloudEvents type, `supportDiagnosticType`.
  public let type: String
  /// The time of the report, in ISO 8601.
  public let time: String
  /// The media type of ``data``, `application/json`.
  public let datacontenttype: String
  /// The schema of ``data``.
  public let dataschema: String
  /// The content of the report.
  public let data: Payload

  /// The keys of the JSON encoding.
  private enum CodingKeys: String, CodingKey {
    /// The `specversion` key.
    case specversion
    /// The `id` key.
    case id
    /// The `source` key.
    case source
    /// The `type` key.
    case type
    /// The `time` key.
    case time
    /// The `datacontenttype` key.
    case datacontenttype
    /// The `dataschema` key.
    case dataschema
    /// The `data` key.
    case data
  }

  /// Creates a redacted report from application service and local diagnostic snapshots.
  public init(
    generatedAt: Date,
    buildIdentity: BuildIdentity,
    osName: String,
    osVersion: String,
    architecture: String,
    inputRead: PermissionManager.AccessState,
    applicationServiceInstalled: Bool,
    applicationServiceConnected: Bool,
    applicationServiceHealth: ApplicationServiceManager.ApplicationServiceHealth?,
    systemGamepadAudit: SystemGamepadSupportAudit? = nil,
    frameTimings: [ControllerFrameTimings] = [],
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
      buildIdentity: buildIdentity,
      osName: osName,
      osVersion: osVersion,
      architecture: architecture
    )
    let permissions = Permissions(
      inputRead: inputRead,
      inputInject: status?.inputInject ?? .unknown
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
        protocolBinding: $0.protocolBinding.rawValue,
        connection: $0.connection,
        serialNumberPresent: $0.serialNumber?.isEmpty == false,
        parameters: $0.parameters.sorted(),
        binding: $0.bindingResult,
        inputEndpoint: $0.inputEndpoint,
        outputEndpoint: $0.outputEndpoint,
        needsSetConfiguration: $0.needsSetConfiguration,
        postHandshakeSettleMilliseconds: $0.postHandshakeSettleMs,
        preferredBackends: $0.preferredBackends.sorted(),
        physicalOutputCapabilities: $0.physicalOutputCapabilities,
        connectionState: $0.connectionState,
        sessionState: $0.sessionState,
        startupCommandStatus: $0.startupCommandStatus,
        inputHealth: $0.inputHealth
      )
    }.sorted {
      if $0.vendorID != $1.vendorID { return $0.vendorID < $1.vendorID }
      if $0.productID != $1.productID { return $0.productID < $1.productID }
      return $0.name < $1.name
    }
    // The service reports unbound devices in a total order; the report keeps it.
    let unboundDevices = (status?.unboundDevices ?? []).map {
      UnboundDevice(
        vendorID: $0.vendorID,
        productID: $0.productID,
        connection: $0.connection,
        binding: $0.bindingResult
      )
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
      "Serial values, paths, packet payloads, HID locations, and discovery text are excluded.",
    ]
    if status == nil { reportNotes.append("Application service status was unavailable.") }
    if virtualDiagnostics == nil {
      reportNotes.append("Virtual-device diagnostics were unavailable.")
    }
    if systemGamepadAudit == nil {
      reportNotes.append("System gamepad catalog audit was unavailable.")
    }
    data = Payload(
      apiVersion: OpenJoystickDriverAPI.version,
      kind: "SupportDiagnostic",
      privacy: privacy,
      system: system,
      permissions: permissions,
      applicationService: applicationService,
      configuration: configuration,
      controllers: controllers,
      unboundDevices: unboundDevices,
      hidGamepads: hidGamepads,
      systemGamepadAudit: systemGamepadAudit,
      frameTimings: frameTimings,
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
