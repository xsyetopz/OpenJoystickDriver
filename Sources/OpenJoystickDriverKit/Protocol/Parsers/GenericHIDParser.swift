import Foundation
import SwiftUSB

/// Descriptor-driven fallback parser for unrecognized HID game controllers.
///
/// Raw report layouts vary between devices, so IOKit decodes descriptor elements
/// and this parser maps standard Generic Desktop and Button usages.
public final class GenericHIDParser: InputParser, HIDElementValueParser, @unchecked Sendable {
  private let identifier: DeviceIdentifier
  private let stateLock = NSLock()
  private var pressedButtons: Set<Button> = []
  private var leftX: Float = 0
  private var leftY: Float = 0
  private var rightX: Float = 0
  private var rightY: Float = 0

  /// Creates a new GenericHIDParser for the given device identifier.
  public init(identifier: DeviceIdentifier) {
    self.identifier = identifier
    print("[GenericHIDParser] Unrecognized controller \(identifier), using HID descriptors")
  }

  // swiftlint:disable async_without_await
  /// No-op; generic HID controllers require no handshake.
  public func performHandshake(handle: USBDeviceHandle?) async throws {}
  // swiftlint:enable async_without_await

  /// Raw reports are handled through IOKit's descriptor-decoded element callback.
  public func parse(data _: Data) throws -> [ControllerEvent] { [] }

  /// Maps standard HID usages while preserving paired stick coordinates.
  public func parse(elementValue value: HIDElementValue) -> [ControllerEvent] {
    stateLock.withLock {
      switch value.usagePage {
      case 0x09:
        return parseButton(value)
      case 0x01:
        return parseGenericDesktop(value)
      default:
        return []
      }
    }
  }

  private func parseButton(_ value: HIDElementValue) -> [ControllerEvent] {
    guard let button = Self.button(for: value.usage) else { return [] }
    let isPressed = value.integerValue != 0
    let wasPressed = pressedButtons.contains(button)
    guard isPressed != wasPressed else { return [] }
    if isPressed {
      pressedButtons.insert(button)
      return [.buttonPressed(button)]
    }
    pressedButtons.remove(button)
    return [.buttonReleased(button)]
  }

  private func parseGenericDesktop(_ value: HIDElementValue) -> [ControllerEvent] {
    switch value.usage {
    case 0x30:
      leftX = Self.normalizedAxis(value)
      return [.leftStickChanged(x: leftX, y: leftY)]
    case 0x31:
      leftY = -Self.normalizedAxis(value)
      return [.leftStickChanged(x: leftX, y: leftY)]
    case 0x32:
      return [.leftTriggerChanged(Self.normalizedTrigger(value))]
    case 0x33:
      rightX = Self.normalizedAxis(value)
      return [.rightStickChanged(x: rightX, y: rightY)]
    case 0x34:
      rightY = -Self.normalizedAxis(value)
      return [.rightStickChanged(x: rightX, y: rightY)]
    case 0x35:
      return [.rightTriggerChanged(Self.normalizedTrigger(value))]
    case 0x39:
      return [.dpadChanged(Self.hatDirection(value))]
    default:
      return []
    }
  }

  private static func normalizedAxis(_ value: HIDElementValue) -> Float {
    let span = value.logicalMaximum - value.logicalMinimum
    guard span > 0 else { return 0 }
    let unit = Float(value.integerValue - value.logicalMinimum) / Float(span)
    return min(1, max(-1, unit * 2 - 1))
  }

  private static func normalizedTrigger(_ value: HIDElementValue) -> Float {
    let span = value.logicalMaximum - value.logicalMinimum
    guard span > 0 else { return 0 }
    let unit = Float(value.integerValue - value.logicalMinimum) / Float(span)
    return min(1, max(0, unit))
  }

  private static func hatDirection(_ value: HIDElementValue) -> DpadDirection {
    let position = value.integerValue - value.logicalMinimum
    guard position >= 0, position < 8 else { return .neutral }
    return [
      .north, .northEast, .east, .southEast,
      .south, .southWest, .west, .northWest,
    ][position]
  }

  private static func button(for usage: UInt32) -> Button? {
    let standard: [Button] = [
      .a, .b, .x, .y, .leftBumper, .rightBumper,
      .back, .start, .leftStick, .rightStick, .guide,
      .genericButton1, .genericButton2, .genericButton3, .genericButton4,
      .genericButton5, .genericButton6, .genericButton7, .genericButton8,
    ]
    guard usage > 0, usage <= standard.count else { return nil }
    return standard[Int(usage - 1)]
  }
}
