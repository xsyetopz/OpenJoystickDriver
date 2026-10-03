/// The values one controller's virtual gamepad last reported, after stick transfer and remapping.
///
/// Stick and trigger values are the virtual device's signed 16-bit axes; stick Y points down, as
/// in the HID report.
public struct ApplicationServiceVirtualOutputState: Codable, Equatable, Sendable {
  /// Virtual button bits; bit `n` is HID button `n + 1`.
  public let buttons: UInt32
  public let hat: HatDirection
  public let leftStickX: Int16
  public let leftStickY: Int16
  public let rightStickX: Int16
  public let rightStickY: Int16
  /// Trigger values including a full press from a digital trigger.
  public let leftTrigger: Int16
  public let rightTrigger: Int16

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
