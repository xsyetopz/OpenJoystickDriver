import IOKit.hid

/// Identifier of one exact published virtual HID ABI.
///
/// These are the only two virtual profiles OJD recognizes. Decoding any other raw value fails,
/// including the retired virtual HID identity names.
public enum VirtualHIDProfileID: String, CaseIterable, Codable, Sendable {
  case xboxOneSBluetooth = "hid-xbox-one-s-bt"
  case generic = "hid-generic"

  /// The profile this identifier names.
  public func makeProfile() throws -> any VirtualHIDProfile {
    switch self {
    case .xboxOneSBluetooth: return try XboxOneSBluetoothHIDProfile()
    case .generic: return OJDGenericHIDProfile()
    }
  }

  /// The identity the profile publishes, readable without building its report format.
  public var identity: VirtualDeviceProfile {
    switch self {
    case .xboxOneSBluetooth: return .xboxOneS
    case .generic: return .openJoystickDriverGenericHID
    }
  }

  /// Every normalized control this profile's layout can carry, which is what profile selection
  /// checks a controller's required primary controls against.
  public var representableControls: Set<ControlID> {
    switch self {
    // The Xbox layout. Guide stays out until a genuine 045E:02FD capture shows whether ordinary
    // HID clients see it, although today's report still carries it as button usage 11.
    case .xboxOneSBluetooth: return ControlID.xboxLayout
    // The generic layout: the frozen 32 buttons, the hat and the six named axes. Today's report
    // carries only its first 16 buttons.
    case .generic:
      return [
        .faceSouth, .faceEast, .faceWest, .faceNorth, .leftShoulder, .rightShoulder,
        .leftTriggerButton, .rightTriggerButton, .view, .menu, .leftStickClick, .rightStickClick,
        .guide, .share, .capture, .touchpadClick, .paddleLeft1, .paddleLeft2, .paddleRight1,
        .paddleRight2, .auxiliary1, .auxiliary2, .auxiliary3, .auxiliary4, .auxiliary5, .auxiliary6,
        .auxiliary7, .auxiliary8, .leftStickTouch, .rightStickTouch, .leftTrackpadClick,
        .rightTrackpadClick, .dpad, .leftStickX, .leftStickY, .rightStickX, .rightStickY,
        .leftTrigger, .rightTrigger,
      ]
    }
  }
}

/// One exact virtual HID ABI: the published identity, the report descriptor, and the codec
/// between the normalized model and that descriptor's reports.
public protocol VirtualHIDProfile: Sendable {
  var id: VirtualHIDProfileID { get }

  /// Identity properties the publisher sets: vendor and product IDs, version, product and
  /// manufacturer strings, and the virtual transport. The per-controller serial is not part of
  /// the profile.
  var identity: VirtualDeviceProfile { get }

  /// Complete HID report descriptor bytes.
  var descriptor: [UInt8] { get }

  /// The report format this approximation wraps, which the user-space publisher composes with
  /// `identity`.
  var reportFormat: any VirtualGamepadReportFormat { get }

  /// The complete input report, including its report ID byte, for `state`.
  func inputReport(for state: ControllerState) -> [UInt8]

  /// Decodes a consumer's output report, as delivered with its report ID byte, into the command
  /// it requests; nil when the report is not one this profile declares, or is malformed.
  func consumerOutput(
    type: IOHIDReportType,
    reportID: UInt32,
    bytes: [UInt8]
  ) -> ControllerOutputCommand?
}

/// `hid-xbox-one-s-bt` over today's hand-authored approximation, not a verified Microsoft ABI.
///
/// The identity is the existing `VirtualDeviceProfile.xboxOneS` (045E:02FD). The descriptor and
/// input layout are `XboxGeckoHIDReportFormat`'s: the One S Bluetooth descriptor with its 16-byte
/// report 1 (no Share field) and Guide also sent alone in report 2, with share and the d-pad
/// button bits never set. It is an approximation until the descriptor and codec are replaced
/// byte-exactly from a genuine 045E:02FD capture.
struct XboxOneSBluetoothHIDProfile: VirtualHIDProfile {
  let id = VirtualHIDProfileID.xboxOneSBluetooth
  private let format: XboxGeckoHIDReportFormat

  init() throws { format = try XboxGeckoHIDReportFormat() }

  var identity: VirtualDeviceProfile { id.identity }
  var descriptor: [UInt8] { format.descriptor }
  var reportFormat: any VirtualGamepadReportFormat { format }

  func inputReport(for state: ControllerState) -> [UInt8] {
    ReportFormatCodec.inputReport(for: state, in: format)
  }

  func consumerOutput(
    type: IOHIDReportType,
    reportID: UInt32,
    bytes: [UInt8]
  ) -> ControllerOutputCommand? {
    ReportFormatCodec.consumerOutput(type: type, reportID: reportID, bytes: bytes, in: format)
  }
}

/// `hid-generic` over the OJD generic gamepad, an approximation of the specified ABI.
///
/// The identity is `VirtualDeviceProfile.openJoystickDriverGenericHID` (1209:4A4F), and the
/// descriptor is `OJDGenericGamepadFormat`'s input-only layout: 16 buttons with the d-pad as four
/// of them, no hat, four stick axes and two trigger axes, and no output report, so the profile
/// decodes no consumer output. pid.codes allocated the ID.
struct OJDGenericHIDProfile: VirtualHIDProfile {
  let id = VirtualHIDProfileID.generic
  private let format = OJDGenericGamepadFormat()

  var identity: VirtualDeviceProfile { id.identity }
  var descriptor: [UInt8] { format.descriptor }
  var reportFormat: any VirtualGamepadReportFormat { format }

  func inputReport(for state: ControllerState) -> [UInt8] {
    ReportFormatCodec.inputReport(for: state, in: format)
  }

  func consumerOutput(
    type: IOHIDReportType,
    reportID: UInt32,
    bytes: [UInt8]
  ) -> ControllerOutputCommand? { nil }
}

/// The adapter from a profile's contract to the report format it wraps.
private enum ReportFormatCodec {
  /// Encodes canonical state through the dispatcher's mapping, without its stick dead zone,
  /// which is output policy rather than part of the ABI.
  static func inputReport(
    for state: ControllerState,
    in format: some VirtualGamepadReportFormat
  ) -> [UInt8] {
    var virtual = VirtualGamepadState()
    UserSpaceOutputDispatcher.apply(
      state,
      labels: .standard,
      stickTransfer: .init(deadzone: 0, rescalesDeadzone: false),
      to: &virtual
    )
    return format.buildInputReport(from: virtual)
  }

  /// Decodes an output report through the consumer output codec that the published device's
  /// set-report callback uses.
  static func consumerOutput(
    type: IOHIDReportType,
    reportID: UInt32,
    bytes: [UInt8],
    in format: some VirtualGamepadReportFormat
  ) -> ControllerOutputCommand? {
    guard type == kIOHIDReportTypeOutput,
      let request = try? VirtualHostReportRequest(type: .output, reportID: reportID, bytes: bytes)
    else { return nil }
    return try? ConsumerOutputCodec.decode(request, in: format)
  }
}
