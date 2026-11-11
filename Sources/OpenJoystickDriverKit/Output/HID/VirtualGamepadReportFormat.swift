import Foundation

/// Normalized virtual gamepad state used by all output backends.
public struct VirtualGamepadState: Sendable {
  /// The pressed buttons, one bit each by ``GamepadHIDDescriptor/ButtonBit``.
  public var buttons: UInt32
  /// The left stick's horizontal position, as a signed 16-bit value.
  public var leftStickX: Int16
  /// The left stick's vertical position, as a signed 16-bit value.
  public var leftStickY: Int16
  /// The right stick's horizontal position, as a signed 16-bit value.
  public var rightStickX: Int16
  /// The right stick's vertical position, as a signed 16-bit value.
  public var rightStickY: Int16
  /// The left trigger pressure, `0...Int16.max`.
  public var leftTrigger: Int16
  /// The right trigger pressure, `0...Int16.max`.
  public var rightTrigger: Int16
  /// Whether the left trigger counts as pressed.
  public var leftTriggerPressed: Bool
  /// Whether the right trigger counts as pressed.
  public var rightTriggerPressed: Bool
  /// The D-pad direction.
  public var hat: GamepadHIDDescriptor.Hat

  /// The left trigger value: the analog pressure, or full when the trigger counts as pressed and
  /// has no analog pressure.
  public var effectiveLeftTrigger: Int16 {
    leftTrigger > 0 ? leftTrigger : (leftTriggerPressed ? Int16.max : 0)
  }
  /// The right trigger value: the analog pressure, or full when the trigger counts as pressed and
  /// has no analog pressure.
  public var effectiveRightTrigger: Int16 {
    rightTrigger > 0 ? rightTrigger : (rightTriggerPressed ? Int16.max : 0)
  }

  /// Creates a state; every part is neutral unless given.
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
    hat: GamepadHIDDescriptor.Hat = .neutral
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
    self.hat = hat
  }
}

/// The HID descriptor of a virtual gamepad and the builder of its report bytes.
///
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

  /// Builds the additional input reports, each beginning with its own Report ID byte, that carry
  /// state the primary report does not (for example a Guide button declared as a separate
  /// report). Delivery sends each one when its bytes change.
  func buildAuxiliaryInputReports(from state: VirtualGamepadState) -> [[UInt8]]
}

extension VirtualGamepadReportFormat {
  /// The default builds no auxiliary report.
  public func buildAuxiliaryInputReports(from _: VirtualGamepadState) -> [[UInt8]] { [] }
  /// The default declares no output report.
  public var outputReportPayloadSize: Int? { nil }
  /// The default declares no output report ID.
  public var outputReportID: UInt8? { nil }
}

/// Generic OJD HID GamePad format (matches ``GamepadHIDDescriptor``).
///
/// Input-only: it declares no output report.
public struct OJDGenericGamepadFormat: VirtualGamepadReportFormat {
  /// The generic descriptor.
  public let descriptor: [UInt8] = GamepadHIDDescriptor.descriptor
  /// The size of the generic input report.
  public let inputReportPayloadSize: Int = GamepadHIDDescriptor.reportSize
  /// The generic format has no report ID.
  public let inputReportID: UInt8? = nil

  /// Creates the format.
  public init() {}

  /// The 14-byte generic input report of `state`.
  public func buildInputReport(from state: VirtualGamepadState) -> [UInt8] {
    var r = [UInt8](repeating: 0, count: GamepadHIDDescriptor.reportSize)
    var buttons: UInt32 = 0
    let sourceBits = [0, 1, 2, 3, 4, 5, 9, 8, 6, 7, 11, 12, 13, 14, 10, 15]
    for (destination, source) in sourceBits.enumerated()
    where state.buttons & (1 << UInt32(source)) != 0 { buttons |= 1 << UInt32(destination) }
    r[0] = UInt8(buttons & 0xFF)
    r[1] = UInt8((buttons >> 8) & 0xFF)
    let lsxB = state.leftStickX.littleEndianBytes
    r[2] = lsxB.0
    r[3] = lsxB.1
    let lsyB = state.leftStickY.littleEndianBytes
    r[4] = lsyB.0
    r[5] = lsyB.1
    let rsxB = state.rightStickX.littleEndianBytes
    r[6] = rsxB.0
    r[7] = rsxB.1
    let rsyB = state.rightStickY.littleEndianBytes
    r[8] = rsyB.0
    r[9] = rsyB.1
    let ltB = state.effectiveLeftTrigger.littleEndianBytes
    r[10] = ltB.0
    r[11] = ltB.1
    let rtB = state.effectiveRightTrigger.littleEndianBytes
    r[12] = rtB.0
    r[13] = rtB.1
    return r
  }
}
