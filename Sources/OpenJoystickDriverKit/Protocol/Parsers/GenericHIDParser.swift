import Foundation

/// Descriptor-driven fallback parser for unrecognized HID game controllers.
///
/// Raw report layouts vary between devices, so IOKit decodes descriptor elements
/// and this parser maps standard Generic Desktop and Button usages.
public final class GenericHIDParser: InputParser, HIDElementValueParser {
  private static let buttonUsagePage: UInt32 = 0x09
  private static let genericDesktopUsagePage: UInt32 = 0x01
  private static let simulationControlsUsagePage: UInt32 = 0x02
  private static let usageX: UInt32 = 0x30
  private static let usageY: UInt32 = 0x31
  private static let usageZ: UInt32 = 0x32
  private static let usageRx: UInt32 = 0x33
  private static let usageRy: UInt32 = 0x34
  private static let usageRz: UInt32 = 0x35
  private static let usageHatSwitch: UInt32 = 0x39
  private static let usageAccelerator: UInt32 = 0xC4
  private static let usageBrake: UInt32 = 0xC5
  private static let wr007VendorID: UInt16 = 0x11C1
  private static let wr007ProductID: UInt16 = 0x5600
  private static let envisionVendorID: UInt16 = 0x2E95
  private static let envisionProductID: UInt16 = 0x434D
  private static let gameSirK1VendorID: UInt16 = 0x3537
  private static let gameSirK1ProductID: UInt16 = 0x1082

  private enum AxisLayout {
    case standard
    case wr007
    /// WR-007 usages with Brake as the left trigger and Accelerator as the right.
    case gameSirK1
    case envision

    var usesSimulationTriggers: Bool { self == .wr007 || self == .gameSirK1 }
  }

  private let identifier: DeviceIdentifier
  private let stateLock = NSLock()
  private var pressedButtons: Set<Button> = []
  private var leftX: Float = 0
  private var leftY: Float = 0
  private var rightX: Float = 0
  private var rightY: Float = 0
  private let axisLayout: AxisLayout

  /// Creates a new GenericHIDParser for the given device identifier.
  public init(identifier: DeviceIdentifier) {
    self.identifier = identifier
    if identifier.vendorID == Self.wr007VendorID && identifier.productID == Self.wr007ProductID {
      axisLayout = .wr007
    } else if identifier.vendorID == Self.envisionVendorID
      && identifier.productID == Self.envisionProductID
    {
      axisLayout = .envision
    } else if identifier.vendorID == Self.gameSirK1VendorID
      && identifier.productID == Self.gameSirK1ProductID
    {
      axisLayout = .gameSirK1
    } else {
      axisLayout = .standard
    }
    print("[GenericHIDParser] Unrecognized controller \(identifier), using HID descriptors")
  }

  /// No-op; generic HID controllers require no handshake.
  /// Raw reports are handled through IOKit's descriptor-decoded element callback.
  public func parse(data _: Data) throws -> [ControllerEvent] { [] }

  public func acceptsElement(usagePage: UInt32, usage: UInt32) -> Bool {
    switch usagePage {
    case Self.buttonUsagePage: button(for: usage) != nil && (axisLayout != .envision || usage <= 10)
    case Self.genericDesktopUsagePage:
      [
        Self.usageX, Self.usageY, Self.usageZ, Self.usageRx, Self.usageRy, Self.usageRz,
        Self.usageHatSwitch,
      ].contains(usage)
    case Self.simulationControlsUsagePage:
      axisLayout.usesSimulationTriggers && [Self.usageAccelerator, Self.usageBrake].contains(usage)
    default: false
    }
  }

  /// Maps standard HID usages while preserving paired stick coordinates.
  public func parse(elementValue value: HIDElementValue) -> [ControllerEvent] {
    stateLock.withLock {
      guard axisLayout != .envision || value.reportID == 6 else { return [] }
      switch value.usagePage {
      case Self.buttonUsagePage: return parseButton(value)
      case Self.genericDesktopUsagePage: return parseGenericDesktop(value)
      case Self.simulationControlsUsagePage: return parseSimulationControl(value)
      default: return []
      }
    }
  }

  private func parseButton(_ value: HIDElementValue) -> [ControllerEvent] {
    guard axisLayout != .envision || value.usage <= 10 else { return [] }
    guard let button = button(for: value.usage) else { return [] }
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
    let usage = axisLayout == .envision ? Self.envisionAxisUsage(value.usage) : value.usage
    switch usage {
    case Self.usageX:
      leftX = Self.normalizedAxis(value)
      return [.leftStickChanged(x: leftX, y: leftY)]
    case Self.usageY:
      leftY = -Self.normalizedAxis(value)
      return [.leftStickChanged(x: leftX, y: leftY)]
    case Self.usageZ:
      if axisLayout.usesSimulationTriggers {
        rightX = Self.normalizedAxis(value)
        return [.rightStickChanged(x: rightX, y: rightY)]
      }
      return [.leftTriggerChanged(Self.normalizedTrigger(value))]
    case Self.usageRx:
      rightX = Self.normalizedAxis(value)
      return [.rightStickChanged(x: rightX, y: rightY)]
    case Self.usageRy:
      rightY = -Self.normalizedAxis(value)
      return [.rightStickChanged(x: rightX, y: rightY)]
    case Self.usageRz:
      if axisLayout.usesSimulationTriggers {
        rightY = -Self.normalizedAxis(value)
        return [.rightStickChanged(x: rightX, y: rightY)]
      }
      return [.rightTriggerChanged(Self.normalizedTrigger(value))]
    case Self.usageHatSwitch: return [.dpadChanged(Self.hatDirection(value))]
    default: return []
    }
  }

  private static func envisionAxisUsage(_ usage: UInt32) -> UInt32 {
    switch usage {
    case usageZ: usageRx
    case usageRz: usageRy
    case usageRx: usageZ
    case usageRy: usageRz
    default: usage
    }
  }

  private func parseSimulationControl(_ value: HIDElementValue) -> [ControllerEvent] {
    guard axisLayout.usesSimulationTriggers else { return [] }
    switch (axisLayout, value.usage) {
    case (.wr007, Self.usageAccelerator), (.gameSirK1, Self.usageBrake):
      return [.leftTriggerChanged(Self.normalizedTrigger(value))]
    case (.wr007, Self.usageBrake), (.gameSirK1, Self.usageAccelerator):
      return [.rightTriggerChanged(Self.normalizedTrigger(value))]
    default: return []
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
    return [.north, .northEast, .east, .southEast, .south, .southWest, .west, .northWest][position]
  }

  private func button(for usage: UInt32) -> Button? {
    if axisLayout.usesSimulationTriggers {
      if axisLayout == .gameSirK1, usage == 13 { return .guide }
      return [
        1: .a, 2: .b, 4: .x, 5: .y, 7: .leftBumper, 8: .rightBumper, 11: .back, 12: .start,
        14: .leftStick, 15: .rightStick,
      ][usage]
    }

    let standard: [Button] = [
      .a, .b, .x, .y, .leftBumper, .rightBumper, .back, .start, .leftStick, .rightStick, .guide,
    ]
    guard usage > 0, usage <= standard.count else { return nil }
    return standard[Int(usage - 1)]
  }
}
