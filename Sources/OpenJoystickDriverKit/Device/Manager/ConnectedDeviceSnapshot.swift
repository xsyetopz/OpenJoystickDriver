/// Point-in-time state of one connected controller pipeline, as ``DeviceManager`` observes it.
public struct ConnectedDeviceSnapshot: Sendable {
  /// Opaque selector for one connected controller during the current runtime session.
  public let runtimeIdentifier: String
  /// Persistent selector for this controller on its USB port; nil without a location ID.
  public let unitIdentifier: String?
  /// Human-readable controller name.
  public let name: String
  /// USB vendor ID.
  public let vendorID: UInt16
  /// USB product ID.
  public let productID: UInt16
  /// Bound protocol family and resolved variant.
  public let protocolBinding: ProtocolBindingID
  /// Connection type (e.g. "USB", "HID").
  public let connection: String
  /// USB interface number the controller is reached through, or nil when none was observed.
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
}
