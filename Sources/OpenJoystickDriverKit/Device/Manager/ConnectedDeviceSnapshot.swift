/// The state of one connected controller's device pipeline at one moment, as the manager sees it.
public struct ConnectedDeviceSnapshot: Sendable {
  /// The controller's key inside the process; it never leaves the service.
  public let logicalControllerID: LogicalControllerID
  /// The token of this attachment; a reconnect issues its own.
  public let sessionToken: ControllerSessionToken
  /// The controller's port key; nil without a location ID.
  public let portKey: ControllerPortKey?
  /// The controller's display name.
  public let name: String
  /// The USB vendor ID.
  public let vendorID: UInt16
  /// The USB product ID.
  public let productID: UInt16
  /// The protocol family and resolved variant that serve the controller.
  public let protocolBinding: ProtocolBindingID
  /// The connection label, such as "USB" or the HID transport property.
  public let connection: String
  /// The USB interface number the controller is reached through; nil when none is observed.
  public let interfaceNumber: UInt8?
  /// The discovery route that owns the controller's pipeline.
  public let discoverySource: DeviceDiscoverySource
  /// The observed physical ownership, which the virtual gamepad exposure policy reads.
  public let physicalOwnership: ControllerOwnershipObservation
  /// Current HID acquisition result; unknown for non-HID discovery routes, except that a raw-USB
  /// controller whose interface another client holds exclusively reports `ownedByAnotherClient`.
  public let hidInputOwnership: HIDInputOwnership
  /// The client that holds the controller's USB interface exclusively; nil when none does or the
  /// interface names none.
  public let inputOwner: USBExclusiveOwner?
  /// The risk that the system also exposes this controller beside OJD's virtual gamepad.
  public let duplicateExposureRisk: DuplicateExposureRisk
  /// The serial number; nil if the device does not report one.
  public let serialNumber: String?
  /// Typed protocol parameters of the controller record, as sorted `name=value` entries.
  public let parameters: [String]
  /// The structured, redacted decision that bound this controller.
  public let bindingResult: ProtocolBindingResult
  /// The interrupt IN endpoint address that the raw-USB route reads.
  public let inputEndpoint: UInt8
  /// The interrupt OUT endpoint address that the raw-USB route writes.
  public let outputEndpoint: UInt8
  /// Whether the raw-USB pipeline calls setConfiguration(1) before it claims the interface.
  public let needsSetConfiguration: Bool
  /// The settle delay in milliseconds after the protocol handshake.
  public let postHandshakeSettleMs: Int
  /// The virtual gamepad backends that the controller record prefers.
  public let preferredBackends: [String]
  /// Exact source-backed motors and lighting features of the active parser.
  public let physicalOutputCapabilities: PhysicalControllerOutputCapabilities
  /// Who drives the controller's output: `macOS` when it serves the controller natively, so
  /// ``physicalOutputCapabilities`` holds only what macOS leaves undone.
  public let physicalOutputOwner: ControllerServer
  /// Who the record the controller bound with says serves the model; `macOS` when it sets none.
  public let recordServer: ControllerServer
  /// How the controller record reaches the controller; `system` when it names no other route.
  public let recordAccessRoute: ControllerAccessRoute
  /// The record's timing and deadzone values as applied to this controller.
  public let tuning: ControllerTuning
  /// Normalized controls and sample formats the active parser emits for this record.
  public let capabilities: ControllerCapabilities
  /// The link and latest power state of the controller.
  public let connectionState: ControllerConnectionState?
  /// Whether OpenJoystickDriver currently admits input and publishes output for this session.
  public let sessionState: ControllerSessionState
  /// The result of the latest required startup command sequence.
  public let startupCommandStatus: String?
  /// The report freshness and recovery state of the controller's input pipeline.
  public let inputHealth: ControllerInputHealth
}
