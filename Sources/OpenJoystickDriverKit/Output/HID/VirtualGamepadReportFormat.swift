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
  public var hat: GamepadHIDDescriptor.Hat

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
  public func buildAuxiliaryInputReports(from state: VirtualGamepadState) -> [[UInt8]] { [] }
  public var outputReportPayloadSize: Int? { nil }
  public var outputReportID: UInt8? { nil }
}

/// Generic OJD HID GamePad format (matches ``GamepadHIDDescriptor``). Input-only: it declares no
/// output report.
public struct OJDGenericGamepadFormat: VirtualGamepadReportFormat {
  public let descriptor: [UInt8] = GamepadHIDDescriptor.descriptor
  public let inputReportPayloadSize: Int = GamepadHIDDescriptor.reportSize
  public let inputReportID: UInt8? = nil

  public init() {}

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
