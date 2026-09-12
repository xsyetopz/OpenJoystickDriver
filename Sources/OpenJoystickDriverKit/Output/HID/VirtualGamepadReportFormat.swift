import Foundation

/// Normalized virtual gamepad state used by all output backends.
public struct VirtualGamepadState: Sendable {
  public var buttons: UInt32
  public var leftStickX: Int16
  public var leftStickY: Int16
  public var rightStickX: Int16
  public var rightStickY: Int16
  public var leftTrigger: Int16
  public var rightTrigger: Int16
  public var leftTriggerPressed: Bool
  public var rightTriggerPressed: Bool
  public var touchpadPressed: Bool
  public var mutePressed: Bool
  public var hat: GamepadHIDDescriptor.Hat
  public var motion: RemappingVirtualMotionState?
  public var motionSamples: [RemappingVirtualMotionState]
  public var motionTimestampNanoseconds: UInt64

  /// Digital-only sources expose a full axis press without replacing analog pressure.
  public var effectiveLeftTrigger: Int16 {
    leftTrigger > 0 ? leftTrigger : (leftTriggerPressed ? Int16.max : 0)
  }
  public var effectiveRightTrigger: Int16 {
    rightTrigger > 0 ? rightTrigger : (rightTriggerPressed ? Int16.max : 0)
  }

  public init(
    buttons: UInt32 = 0,
    leftStickX: Int16 = 0,
    leftStickY: Int16 = 0,
    rightStickX: Int16 = 0,
    rightStickY: Int16 = 0,
    leftTrigger: Int16 = 0,
    rightTrigger: Int16 = 0,
    leftTriggerPressed: Bool = false,
    rightTriggerPressed: Bool = false,
    touchpadPressed: Bool = false,
    mutePressed: Bool = false,
    hat: GamepadHIDDescriptor.Hat = .neutral,
    motion: RemappingVirtualMotionState? = nil,
    motionSamples: [RemappingVirtualMotionState] = [],
    motionTimestampNanoseconds: UInt64 = 0
  ) {
    self.buttons = buttons
    self.leftStickX = leftStickX
    self.leftStickY = leftStickY
    self.rightStickX = rightStickX
    self.rightStickY = rightStickY
    self.leftTrigger = leftTrigger
    self.rightTrigger = rightTrigger
    self.leftTriggerPressed = leftTriggerPressed
    self.rightTriggerPressed = rightTriggerPressed
    self.touchpadPressed = touchpadPressed
    self.mutePressed = mutePressed
    self.hat = hat
    self.motion = motion
    self.motionSamples = motionSamples
    self.motionTimestampNanoseconds = motionTimestampNanoseconds
  }
}

/// Report format for a virtual HID gamepad: descriptor + report bytes builder.
public protocol VirtualGamepadReportFormat: Sendable {
  /// HID report descriptor bytes.
  var descriptor: [UInt8] { get }

  /// Size of one input report *payload* (does not include the optional Report ID byte).
  var inputReportPayloadSize: Int { get }

  /// HID Report ID used for the input report, or nil if the descriptor does not use report IDs.
  var inputReportID: UInt8? { get }

  /// Size of one output report payload, or nil when the descriptor does not accept output reports.
  var outputReportPayloadSize: Int? { get }

  /// HID Report ID used for the output report, or nil if the descriptor does not use report IDs.
  var outputReportID: UInt8? { get }

  /// Builds one complete input report.
  ///
  /// If `inputReportID` is non-nil, the returned bytes MUST begin with that Report ID byte.
  func buildInputReport(from state: VirtualGamepadState) -> [UInt8]

  /// Whether this exact descriptor/report pair carries gyroscope and accelerometer values.
  var supportsMotion: Bool { get }

}

extension VirtualGamepadReportFormat {
  public var outputReportPayloadSize: Int? { nil }
  public var outputReportID: UInt8? { nil }
  public var supportsMotion: Bool { false }
}

/// Generic OJD HID GamePad format (matches ``GamepadHIDDescriptor``).
public struct OJDGenericGamepadFormat: VirtualGamepadReportFormat {
  public let descriptor: [UInt8] = GamepadHIDDescriptor.descriptor
  public let inputReportPayloadSize: Int = GamepadHIDDescriptor.reportSize
  public let inputReportID: UInt8? = nil
  public let outputReportPayloadSize: Int? = GamepadHIDDescriptor.reportSize
  public let outputReportID: UInt8? = nil
  private let includesDpadButtonBits: Bool

  public init(includesDpadButtonBits: Bool = true) {
    self.includesDpadButtonBits = includesDpadButtonBits
  }

  public func buildInputReport(from state: VirtualGamepadState) -> [UInt8] {
    var r = [UInt8](repeating: 0, count: GamepadHIDDescriptor.reportSize)
    let dpadMask: UInt32 = 0xF << 11
    let buttons = includesDpadButtonBits ? state.buttons : (state.buttons & ~dpadMask)
    r[0] = UInt8(buttons & 0xFF)
    r[1] = UInt8((buttons >> 8) & 0xFF)
    let lsxB = state.leftStickX.littleEndianBytes
    r[2] = lsxB.0
    r[3] = lsxB.1
    let lsyB = state.leftStickY.littleEndianBytes
    r[4] = lsyB.0
    r[5] = lsyB.1
    let ltB = state.effectiveLeftTrigger.littleEndianBytes
    r[6] = ltB.0
    r[7] = ltB.1
    let rsxB = state.rightStickX.littleEndianBytes
    r[8] = rsxB.0
    r[9] = rsxB.1
    let rsyB = state.rightStickY.littleEndianBytes
    r[10] = rsyB.0
    r[11] = rsyB.1
    let rtB = state.effectiveRightTrigger.littleEndianBytes
    r[12] = rtB.0
    r[13] = rtB.1
    r[14] = state.hat.rawValue & 0x0F
    return r
  }
}

/// SDL-focused HID GamePad format.
///
/// This keeps the stable OJD button/axis order but deliberately omits the hat
/// switch so SDL does not expose D-pad as an extra axis. D-pad directions are
/// exposed only as buttons 12-15, and triggers are unsigned zero-idle axes so
/// SDL2/SDL3 gamepad trigger axes are neutral at rest.
public struct OJDSDLGamepadFormat: VirtualGamepadReportFormat {
  public let descriptor: [UInt8] = SDLGamepadHIDDescriptor.descriptor
  public let inputReportPayloadSize: Int = SDLGamepadHIDDescriptor.reportSize
  public let inputReportID: UInt8? = nil
  public let outputReportPayloadSize: Int? = SDLGamepadHIDDescriptor.maxOutputReportPayloadSize
  public let outputReportID: UInt8? = nil

  public init() {}

  public func buildInputReport(from state: VirtualGamepadState) -> [UInt8] {
    var r = [UInt8](repeating: 0, count: SDLGamepadHIDDescriptor.reportSize)
    r[0] = UInt8(state.buttons & 0xFF)
    r[1] = UInt8((state.buttons >> 8) & 0xFF)
    let lsxB = state.leftStickX.littleEndianBytes
    r[2] = lsxB.0
    r[3] = lsxB.1
    let lsyB = state.leftStickY.littleEndianBytes
    r[4] = lsyB.0
    r[5] = lsyB.1
    let ltB = state.effectiveLeftTrigger.littleEndianBytes
    r[6] = ltB.0
    r[7] = ltB.1
    let rsxB = state.rightStickX.littleEndianBytes
    r[8] = rsxB.0
    r[9] = rsxB.1
    let rsyB = state.rightStickY.littleEndianBytes
    r[10] = rsyB.0
    r[11] = rsyB.1
    let rtB = state.effectiveRightTrigger.littleEndianBytes
    r[12] = rtB.0
    r[13] = rtB.1
    return r
  }
}
