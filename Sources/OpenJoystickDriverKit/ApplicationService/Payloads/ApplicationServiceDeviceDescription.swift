import Foundation

/// Structured description of a connected controller, used in ``ApplicationServiceStatusPayload``.
public struct ApplicationServiceDeviceDescription: Codable, Sendable {
  /// The token of this attachment; a reconnect gets a new one.
  ///
  /// See ``ControllerSessionToken``.
  public let sessionToken: ControllerSessionToken
  /// The controller's port key, which lasts across reconnects and service restarts; nil when the
  /// controller reports no location ID.
  ///
  /// See ``ControllerPortKey``.
  public let portKey: ControllerPortKey?
  /// Human-readable controller name.
  public let name: String
  /// USB vendor ID.
  public let vendorID: UInt16
  /// USB product ID.
  public let productID: UInt16
  /// Bound protocol family and resolved variant (e.g. `XboxGIP:USB`, `VendorFlydigi`).
  public let protocolBinding: ProtocolBindingID
  /// Connection type (e.g. "USB", "HID").
  public let connection: String
  /// USB interface number the controller is reached through: the claimed interface of a raw-USB
  /// pipeline, or the parent interface observed for a HID connection.
  ///
  /// Nil when none was observed.
  public let interfaceNumber: UInt8?
  /// Discovery route that owns the live controller pipeline.
  public let discoverySource: DeviceDiscoverySource
  /// Observed physical ownership route used by virtual exposure policy.
  public let physicalOwnership: ControllerOwnershipObservation
  /// Current HID acquisition result; unknown for non-HID discovery routes, except that a raw-USB
  /// controller whose interface another client holds exclusively reports `ownedByAnotherClient`.
  public let hidInputOwnership: HIDInputOwnership
  /// The client that holds the controller's USB interface exclusively; nil when none does or the
  /// interface names none.
  public let inputOwner: USBExclusiveOwner?
  /// Duplicate-device risk implied by the current physical ownership observation.
  public let duplicateExposureRisk: DuplicateExposureRisk
  /// USB serial number, or nil if not reported.
  public let serialNumber: String?
  /// Typed protocol parameters of the controller record, as sorted `name=value` entries.
  public let parameters: [String]
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
  public let physicalOutputOwner: ControllerServer
  /// Who the controller record says serves the model after the bundled, package, and user layers:
  /// `ojd` when a layer sets it, `macOS` otherwise.
  ///
  /// Unlike ``physicalOutputOwner``, it stays `ojd` while OJD serves a model that macOS also
  /// supports.
  public let recordServer: ControllerServer
  /// How the controller record reaches the controller; `system` when it names no other route.
  public let recordAccessRoute: ControllerAccessRoute
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
  /// Whether a `Pause` has the controller pass through unmapped; set by the service when it
  /// reports status.
  public var paused = false
  /// The profile in force for the controller and the app that selected it.
  ///
  /// It is nil when no profile is active for it. The service sets it when it reports status.
  public var profileInForce: ApplicationServiceProfileInForce?

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
    inputOwner: USBExclusiveOwner? = nil,
    duplicateExposureRisk: DuplicateExposureRisk = .unknownOwnership,
    serialNumber: String?,
    parameters: [String] = [],
    bindingResult: ProtocolBindingResult,
    inputEndpoint: UInt8 = 0,
    outputEndpoint: UInt8 = 0,
    needsSetConfiguration: Bool = false,
    postHandshakeSettleMs: Int = 0,
    preferredBackends: [String] = [],
    physicalOutputCapabilities: PhysicalControllerOutputCapabilities = .none,
    physicalOutputOwner: ControllerServer = .ojd,
    recordServer: ControllerServer,
    recordAccessRoute: ControllerAccessRoute,
    tuning: ControllerTuning = .none,
    capabilities: ControllerCapabilities = ControllerCapabilities(controls: []),
    connectionState: ControllerConnectionState? = nil,
    sessionState: ControllerSessionState = .active,
    startupCommandStatus: String? = nil,
    inputHealth: ControllerInputHealth = ControllerInputHealth(state: .healthy),
    sessionToken: ControllerSessionToken = .issue(),
    portKey: ControllerPortKey? = nil
  ) {
    self.sessionToken = sessionToken
    self.portKey = portKey
    self.name = name
    self.vendorID = vendorID
    self.productID = productID
    self.protocolBinding = protocolBinding
    self.connection = connection
    self.interfaceNumber = interfaceNumber
    self.discoverySource = discoverySource
    self.physicalOwnership = physicalOwnership
    self.hidInputOwnership = hidInputOwnership
    self.inputOwner = inputOwner
    self.duplicateExposureRisk = duplicateExposureRisk
    self.serialNumber = serialNumber
    self.parameters = parameters
    self.bindingResult = bindingResult
    self.inputEndpoint = inputEndpoint
    self.outputEndpoint = outputEndpoint
    self.needsSetConfiguration = needsSetConfiguration
    self.postHandshakeSettleMs = postHandshakeSettleMs
    self.preferredBackends = preferredBackends
    self.physicalOutputCapabilities = physicalOutputCapabilities
    self.physicalOutputOwner = physicalOutputOwner
    self.recordServer = recordServer
    self.recordAccessRoute = recordAccessRoute
    self.tuning = tuning
    self.capabilities = capabilities
    self.connectionState = connectionState
    self.sessionState = sessionState
    self.startupCommandStatus = startupCommandStatus
    self.inputHealth = inputHealth
  }

  /// Decodes the value from `decoder`.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.sessionToken = try container.decode(ControllerSessionToken.self, forKey: .sessionToken)
    self.portKey = try container.decodeIfPresent(ControllerPortKey.self, forKey: .portKey)
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
    self.inputOwner = try container.decodeIfPresent(USBExclusiveOwner.self, forKey: .inputOwner)
    self.duplicateExposureRisk = try container.decode(
      DuplicateExposureRisk.self,
      forKey: .duplicateExposureRisk
    )
    self.serialNumber = try container.decodeIfPresent(String.self, forKey: .serialNumber)
    self.parameters = try container.decode([String].self, forKey: .parameters)
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
      ControllerServer.self,
      forKey: .physicalOutputOwner
    )
    self.recordServer = try container.decode(ControllerServer.self, forKey: .recordServer)
    self.recordAccessRoute = try container.decode(
      ControllerAccessRoute.self,
      forKey: .recordAccessRoute
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
    self.paused = try container.decode(Bool.self, forKey: .paused)
    self.profileInForce = try container.decodeIfPresent(
      ApplicationServiceProfileInForce.self,
      forKey: .profileInForce
    )
  }

  /// The keys of the JSON encoding.
  private enum CodingKeys: String, CodingKey {
    /// The `name` key.
    case name
    /// The `sessionToken` key.
    case sessionToken
    /// The `portKey` key.
    case portKey
    /// The `vendorID` key.
    case vendorID
    /// The `productID` key.
    case productID
    /// The `protocolBinding` key.
    case protocolBinding
    /// The `connection` key.
    case connection
    /// The `interfaceNumber` key.
    case interfaceNumber
    /// The `discoverySource` key.
    case discoverySource
    /// The `physicalOwnership` key.
    case physicalOwnership
    /// The `hidInputOwnership` key.
    case hidInputOwnership
    /// The `inputOwner` key.
    case inputOwner
    /// The `duplicateExposureRisk` key.
    case duplicateExposureRisk
    /// The `serialNumber` key.
    case serialNumber
    /// The `parameters` key.
    case parameters
    /// The `bindingResult` key.
    case bindingResult
    /// The `inputEndpoint` key.
    case inputEndpoint
    /// The `outputEndpoint` key.
    case outputEndpoint
    /// The `needsSetConfiguration` key.
    case needsSetConfiguration
    /// The `postHandshakeSettleMs` key.
    case postHandshakeSettleMs
    /// The `preferredBackends` key.
    case preferredBackends
    /// The `physicalOutputCapabilities` key.
    case physicalOutputCapabilities
    /// The `physicalOutputOwner` key.
    case physicalOutputOwner
    /// The `recordServer` key.
    case recordServer
    /// The `recordAccessRoute` key.
    case recordAccessRoute
    /// The `tuning` key.
    case tuning
    /// The `capabilities` key.
    case capabilities
    /// The `connectionState` key.
    case connectionState
    /// The `sessionState` key.
    case sessionState
    /// The `startupCommandStatus` key.
    case startupCommandStatus
    /// The `inputHealth` key.
    case inputHealth
    /// The `virtualHIDProfile` key.
    case virtualHIDProfile
    /// The `publication` key.
    case publication
    /// The `paused` key.
    case paused
    /// The `profileInForce` key.
    case profileInForce
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
      inputOwner: snapshot.inputOwner,
      duplicateExposureRisk: snapshot.duplicateExposureRisk,
      serialNumber: snapshot.serialNumber,
      parameters: snapshot.parameters,
      bindingResult: snapshot.bindingResult,
      inputEndpoint: snapshot.inputEndpoint,
      outputEndpoint: snapshot.outputEndpoint,
      needsSetConfiguration: snapshot.needsSetConfiguration,
      postHandshakeSettleMs: snapshot.postHandshakeSettleMs,
      preferredBackends: snapshot.preferredBackends,
      physicalOutputCapabilities: snapshot.physicalOutputCapabilities,
      physicalOutputOwner: snapshot.physicalOutputOwner,
      recordServer: snapshot.recordServer,
      recordAccessRoute: snapshot.recordAccessRoute,
      tuning: snapshot.tuning,
      capabilities: snapshot.capabilities,
      connectionState: snapshot.connectionState,
      sessionState: snapshot.sessionState,
      startupCommandStatus: snapshot.startupCommandStatus,
      inputHealth: snapshot.inputHealth,
      sessionToken: snapshot.sessionToken,
      portKey: snapshot.portKey
    )
  }
}

extension ApplicationServiceDeviceDescription: ControllerReferenceable {
  /// The controller's model.
  public var model: ControllerModelID {
    ControllerModelID(vendorID: vendorID, productID: productID)
  }
}
