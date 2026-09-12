import Foundation

/// A snapshot of the current input state for one controller.
///
/// Updated by ``DevicePipeline`` every time a new input report arrives.
/// Used by the Developer tab to display live button, stick, and trigger values.
public struct DeviceInputState: Codable, Sendable, Equatable {
  /// USB vendor ID of the device this state belongs to.
  public let vendorID: UInt16
  /// USB product ID of the device this state belongs to.
  public let productID: UInt16
  /// Names of buttons currently held down (e.g. `["A", "LB"]`).
  public var pressedButtons: [String]
  /// Left stick horizontal axis, normalized to -1...1.
  public var leftStickX: Float
  /// Left stick vertical axis, normalized to -1...1.
  public var leftStickY: Float
  /// Right stick horizontal axis, normalized to -1...1.
  public var rightStickX: Float
  /// Right stick vertical axis, normalized to -1...1.
  public var rightStickY: Float
  /// Left trigger pressure, normalized to 0...1.
  public var leftTrigger: Float
  /// Right trigger pressure, normalized to 0...1.
  public var rightTrigger: Float
  /// Latest complete contact frame for each explicitly reported touch surface.
  public var touchSamples: [ControllerTouchSample]

  /// Creates a zeroed-out input state for the given device.
  public init(vendorID: UInt16, productID: UInt16) {
    self.vendorID = vendorID
    self.productID = productID
    pressedButtons = []
    leftStickX = 0
    leftStickY = 0
    rightStickX = 0
    rightStickY = 0
    leftTrigger = 0
    rightTrigger = 0
    touchSamples = []
  }

  private enum CodingKeys: String, CodingKey {
    case vendorID
    case productID
    case pressedButtons
    case leftStickX
    case leftStickY
    case rightStickX
    case rightStickY
    case leftTrigger
    case rightTrigger
    case touchSamples
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    vendorID = try values.decode(UInt16.self, forKey: .vendorID)
    productID = try values.decode(UInt16.self, forKey: .productID)
    pressedButtons = try values.decode([String].self, forKey: .pressedButtons)
    leftStickX = try values.decode(Float.self, forKey: .leftStickX)
    leftStickY = try values.decode(Float.self, forKey: .leftStickY)
    rightStickX = try values.decode(Float.self, forKey: .rightStickX)
    rightStickY = try values.decode(Float.self, forKey: .rightStickY)
    leftTrigger = try values.decode(Float.self, forKey: .leftTrigger)
    rightTrigger = try values.decode(Float.self, forKey: .rightTrigger)
    touchSamples =
      try values.decodeIfPresent([ControllerTouchSample].self, forKey: .touchSamples) ?? []
  }
}
