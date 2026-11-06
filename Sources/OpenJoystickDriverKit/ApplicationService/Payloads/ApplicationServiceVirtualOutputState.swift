/// The values one controller's virtual gamepad last reported, after stick transfer and remapping.
///
/// Stick and trigger values are the virtual device's signed 16-bit axes; stick Y points down, as
/// in the HID report.
public struct ApplicationServiceVirtualOutputState: Codable, Equatable, Sendable {
  /// Virtual button bits; bit `n` is HID button `n + 1`.
  public let buttons: UInt32
  /// The hat switch direction.
  public let hat: HatDirection
  /// The left stick's horizontal axis.
  public let leftStickX: Int16
  /// The left stick's vertical axis; positive points down.
  public let leftStickY: Int16
  /// The right stick's horizontal axis.
  public let rightStickX: Int16
  /// The right stick's vertical axis; positive points down.
  public let rightStickY: Int16
  /// Trigger values including a full press from a digital trigger.
  public let leftTrigger: Int16
  /// The right trigger value, including a full press from a digital trigger.
  public let rightTrigger: Int16

  /// Creates the payload from the virtual gamepad's `state`.
  public init(_ state: VirtualGamepadState) {
    buttons = state.buttons
    hat = Self.directions[Int(state.hat.rawValue)]
    leftStickX = state.leftStickX
    leftStickY = state.leftStickY
    rightStickX = state.rightStickX
    rightStickY = state.rightStickY
    leftTrigger = state.effectiveLeftTrigger
    rightTrigger = state.effectiveRightTrigger
  }

  /// Directions in `GamepadHIDDescriptor.Hat` raw-value order.
  private static let directions: [HatDirection] = [
    .neutral, .north, .northEast, .east, .southEast, .south, .southWest, .west, .northWest,
  ]
}
