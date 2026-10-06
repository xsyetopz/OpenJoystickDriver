import Foundation

/// Structured description of a connected controller, used in ``ApplicationServiceStatusPayload``.
public struct ApplicationServiceDeviceDescription: Codable, Sendable {
  /// Opaque selector for one connected controller during the current runtime session.
  public let runtimeIdentifier: String
  /// Persistent selector for this controller on its USB port, which lasts across reconnects and
  /// service restarts; nil when the controller reports no location ID. See ``UnitIdentity``.
  public let unitIdentifier: String?
  /// Human-readable controller name.
  public let name: String
  /// USB vendor ID.
  public let vendorID: UInt16
  /// USB product ID.
  public let productID: UInt16
  /// Bound protocol family and resolved variant (e.g. `xbox.gip:usb`, `vendor.flydigi`).
  public let protocolBinding: ProtocolBindingID
  /// Connection type (e.g. "USB", "HID").
  public let connection: String
  /// USB interface number the controller is reached through: the claimed interface of a raw-USB
  /// pipeline, or the parent interface observed for a HID connection. Nil when none was observed.
  public let interfaceNumber: UInt8?
  /// Discovery route that owns the live controller pipeline.
  public let discoverySource: DeviceDiscoverySource
  /// Observed physical ownership route used by virtual exposure policy.
  public let physicalOwnership: ControllerOwnershipObservation
  /// Current HID acquisition result; unknown for non-HID discovery routes.
  public let hidInputOwnership: HIDInputOwnership
  /// Duplicate-device risk implied by the current physical ownership observation.
  public let duplicateExposureRisk: DuplicateExposureRisk
  /// USB serial number, or nil if not reported.
  public let serialNumber: String?
  /// Driver-declared quirk IDs from the controller record.
  public let quirks: [String]
  /// The structured, redacted decision that bound this controller.
  public let bindingResult: ProtocolBindingResult
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
  /// Who drives the controller's output: `macOS` when it serves the controller natively, so
  /// ``physicalOutputCapabilities`` holds only what macOS leaves undone.
  public let physicalOutputOwner: ControllerOwnership
  /// The record's timing and deadzone values as applied to this controller.
  public let tuning: ControllerTuning
  /// Normalized controls and sample formats the active parser emits for this record.
  public let capabilities: ControllerCapabilities
  /// Link and latest power state of the physical controller.
  public let connectionState: ControllerConnectionState?
  /// Whether OpenJoystickDriver currently admits input and publishes output for this session.
  public let sessionState: ControllerSessionState
  /// Result of the most recent required protocol startup command sequence.
  public let startupCommandStatus: String?
  /// Live report freshness and recovery state for this controller input pipeline.
  public let inputHealth: ControllerInputHealth
  /// Virtual HID profile selection for this controller; set by the service when it reports status.
  public var virtualHIDProfile: ApplicationServiceVirtualHIDProfileStatus?
  /// Whether a virtual device publishes this controller and why not; set by the service when it
  /// reports status.
  public var publication: ApplicationServicePublicationStatus?

  /// Creates a new ApplicationServiceDeviceDescription.
  public init(
    name: String,
    vendorID: UInt16,
    productID: UInt16,
    protocolBinding: ProtocolBindingID,
    connection: String,
    interfaceNumber: UInt8? = nil,
    discoverySource: DeviceDiscoverySource,
    physicalOwnership: ControllerOwnershipObservation = .unknown,
    hidInputOwnership: HIDInputOwnership = .unknown,
    duplicateExposureRisk: DuplicateExposureRisk = .unknownOwnership,
    serialNumber: String?,
    quirks: [String] = [],
    bindingResult: ProtocolBindingResult,
    inputEndpoint: UInt8 = 0,
    outputEndpoint: UInt8 = 0,
    needsSetConfiguration: Bool = false,
    postHandshakeSettleMs: Int = 0,
    preferredBackends: [String] = [],
    physicalOutputCapabilities: PhysicalControllerOutputCapabilities = .none,
    physicalOutputOwner: ControllerOwnership = .ojd,
    tuning: ControllerTuning = .none,
    capabilities: ControllerCapabilities = ControllerCapabilities(controls: []),
    connectionState: ControllerConnectionState? = nil,
    sessionState: ControllerSessionState = .active,
    startupCommandStatus: String? = nil,
    inputHealth: ControllerInputHealth = ControllerInputHealth(state: .healthy),
    runtimeIdentifier: String? = nil,
    unitIdentifier: String? = nil
  ) {
    self.runtimeIdentifier = runtimeIdentifier ?? String(format: "%04X:%04X:M", vendorID, productID)
    self.unitIdentifier = unitIdentifier
    self.name = name
    self.vendorID = vendorID
    self.productID = productID
    self.protocolBinding = protocolBinding
    self.connection = connection
    self.interfaceNumber = interfaceNumber
    self.discoverySource = discoverySource
    self.physicalOwnership = physicalOwnership
    self.hidInputOwnership = hidInputOwnership
    self.duplicateExposureRisk = duplicateExposureRisk
    self.serialNumber = serialNumber
    self.quirks = quirks
    self.bindingResult = bindingResult
    self.inputEndpoint = inputEndpoint
    self.outputEndpoint = outputEndpoint
    self.needsSetConfiguration = needsSetConfiguration
    self.postHandshakeSettleMs = postHandshakeSettleMs
    self.preferredBackends = preferredBackends
    self.physicalOutputCapabilities = physicalOutputCapabilities
    self.physicalOutputOwner = physicalOutputOwner
    self.tuning = tuning
    self.capabilities = capabilities
    self.connectionState = connectionState
    self.sessionState = sessionState
    self.startupCommandStatus = startupCommandStatus
    self.inputHealth = inputHealth
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.runtimeIdentifier = try container.decode(String.self, forKey: .runtimeIdentifier)
    self.unitIdentifier = try container.decodeIfPresent(String.self, forKey: .unitIdentifier)
    self.name = try container.decode(String.self, forKey: .name)
    self.vendorID = try container.decode(UInt16.self, forKey: .vendorID)
    self.productID = try container.decode(UInt16.self, forKey: .productID)
    self.protocolBinding = try container.decode(ProtocolBindingID.self, forKey: .protocolBinding)
    self.connection = try container.decode(String.self, forKey: .connection)
    self.interfaceNumber = try container.decodeIfPresent(UInt8.self, forKey: .interfaceNumber)
    self.discoverySource = try container.decode(
      DeviceDiscoverySource.self,
      forKey: .discoverySource
    )
    self.physicalOwnership = try container.decode(
      ControllerOwnershipObservation.self,
      forKey: .physicalOwnership
    )
    self.hidInputOwnership = try container.decode(
      HIDInputOwnership.self,
      forKey: .hidInputOwnership
    )
    self.duplicateExposureRisk = try container.decode(
      DuplicateExposureRisk.self,
      forKey: .duplicateExposureRisk
    )
    self.serialNumber = try container.decodeIfPresent(String.self, forKey: .serialNumber)
    self.quirks = try container.decode([String].self, forKey: .quirks)
    self.bindingResult = try container.decode(ProtocolBindingResult.self, forKey: .bindingResult)
    self.inputEndpoint = try container.decode(UInt8.self, forKey: .inputEndpoint)
    self.outputEndpoint = try container.decode(UInt8.self, forKey: .outputEndpoint)
    self.needsSetConfiguration = try container.decode(Bool.self, forKey: .needsSetConfiguration)
    self.postHandshakeSettleMs = try container.decode(Int.self, forKey: .postHandshakeSettleMs)
    self.preferredBackends = try container.decode([String].self, forKey: .preferredBackends)
    self.physicalOutputCapabilities = try container.decode(
      PhysicalControllerOutputCapabilities.self,
      forKey: .physicalOutputCapabilities
    )
    self.physicalOutputOwner = try container.decode(
      ControllerOwnership.self,
      forKey: .physicalOutputOwner
    )
    self.tuning = try container.decode(ControllerTuning.self, forKey: .tuning)
    self.capabilities = try container.decode(ControllerCapabilities.self, forKey: .capabilities)
    self.connectionState = try container.decodeIfPresent(
      ControllerConnectionState.self,
      forKey: .connectionState
    )
    self.sessionState = try container.decode(ControllerSessionState.self, forKey: .sessionState)
    self.startupCommandStatus = try container.decodeIfPresent(
      String.self,
      forKey: .startupCommandStatus
    )
    self.inputHealth = try container.decode(ControllerInputHealth.self, forKey: .inputHealth)
    self.virtualHIDProfile = try container.decodeIfPresent(
      ApplicationServiceVirtualHIDProfileStatus.self,
      forKey: .virtualHIDProfile
    )
    self.publication = try container.decodeIfPresent(
      ApplicationServicePublicationStatus.self,
      forKey: .publication
    )
  }

  private enum CodingKeys: String, CodingKey {
    case name
    case runtimeIdentifier
    case unitIdentifier
    case vendorID
    case productID
    case protocolBinding
    case connection
    case interfaceNumber
    case discoverySource
    case physicalOwnership
    case hidInputOwnership
    case duplicateExposureRisk
    case serialNumber
    case quirks
    case bindingResult
    case inputEndpoint
    case outputEndpoint
    case needsSetConfiguration
    case postHandshakeSettleMs
    case preferredBackends
    case physicalOutputCapabilities
    case physicalOutputOwner
    case tuning
    case capabilities
    case connectionState
    case sessionState
    case startupCommandStatus
    case inputHealth
    case virtualHIDProfile
    case publication
  }
}

extension ApplicationServiceDeviceDescription {
  /// Describes a controller from its device snapshot; the service sets its virtual HID profile.
  package init(snapshot: ConnectedDeviceSnapshot) {
    self.init(
      name: snapshot.name,
      vendorID: snapshot.vendorID,
      productID: snapshot.productID,
      protocolBinding: snapshot.protocolBinding,
      connection: snapshot.connection,
      interfaceNumber: snapshot.interfaceNumber,
      discoverySource: snapshot.discoverySource,
      physicalOwnership: snapshot.physicalOwnership,
      hidInputOwnership: snapshot.hidInputOwnership,
      duplicateExposureRisk: snapshot.duplicateExposureRisk,
      serialNumber: snapshot.serialNumber,
      quirks: snapshot.quirks,
      bindingResult: snapshot.bindingResult,
      inputEndpoint: snapshot.inputEndpoint,
      outputEndpoint: snapshot.outputEndpoint,
      needsSetConfiguration: snapshot.needsSetConfiguration,
      postHandshakeSettleMs: snapshot.postHandshakeSettleMs,
      preferredBackends: snapshot.preferredBackends,
      physicalOutputCapabilities: snapshot.physicalOutputCapabilities,
      physicalOutputOwner: snapshot.physicalOutputOwner,
      tuning: snapshot.tuning,
      capabilities: snapshot.capabilities,
      connectionState: snapshot.connectionState,
      sessionState: snapshot.sessionState,
      startupCommandStatus: snapshot.startupCommandStatus,
      inputHealth: snapshot.inputHealth,
      runtimeIdentifier: snapshot.runtimeIdentifier,
      unitIdentifier: snapshot.unitIdentifier
    )
  }
}
