import Foundation

/// Descriptor-driven driver for the `hid.descriptor` protocol: HID controllers whose
/// report descriptor satisfies ``HIDDescriptorContract``.
///
/// Raw report layouts vary between devices, so IOKit decodes descriptor elements
/// and this driver maps standard Generic Desktop, Simulation, Button, and Consumer usages.
public final class HIDDescriptorDriver: PhysicalProtocolDriver {
  private static let buttonUsagePage: UInt32 = 0x09
  private static let genericDesktopUsagePage: UInt32 = 0x01
  private static let simulationControlsUsagePage: UInt32 = 0x02
  private static let consumerUsagePage: UInt32 = 0x0C
  private static let usageX: UInt32 = 0x30
  private static let usageY: UInt32 = 0x31
  private static let usageZ: UInt32 = 0x32
  private static let usageRx: UInt32 = 0x33
  private static let usageRy: UInt32 = 0x34
  private static let usageRz: UInt32 = 0x35
  private static let usageHatSwitch: UInt32 = 0x39
  private static let usageSystemMainMenu: UInt32 = 0x85
  private static let usageAccelerator: UInt32 = 0xC4
  private static let usageBrake: UInt32 = 0xC5
  private static let usageRecord: UInt32 = 0xB2
  private static let usageACHome: UInt32 = 0x223
  private static let usageACBack: UInt32 = 0x224
  private static let wr007VendorID: UInt16 = 0x11C1
  private static let wr007ProductID: UInt16 = 0x5600
  private static let envisionVendorID: UInt16 = 0x2E95
  private static let envisionProductID: UInt16 = 0x434D
  /// 8BitDo Ultimate 2C Wireless over Bluetooth LE (`2DC8:301B`) and its HID receiver
  /// (`2DC8:301C`), whose descriptors are not recorded; others are detected from the descriptor.
  private static let zRzBrakeLeftDevices: Set<[UInt16]> = [[0x2DC8, 0x301B], [0x2DC8, 0x301C]]
  /// DragonRise generic USB PCB (`0079:0006`), sold under several gamepad brands.
  private static let dragonRiseDevice: [UInt16] = [0x0079, 0x0006]

  private enum AxisLayout {
    case standard
    case wr007
    case envision
    /// WR007's Z/Rz right stick and button order, with Brake as LT and a Home button.
    case zRzBrakeLeft
    /// DragonRise's Z/Rz right stick and DirectInput button order: 1-4 are Y, B, A, X, and 7-8
    /// are digital L2 and R2.
    case dragonRise

    var zRzIsRightStick: Bool { self == .wr007 || self == .zRzBrakeLeft || self == .dragonRise }
  }

  private let identifier: DeviceIdentifier
  private var state = ControllerState.neutral
  /// Stick axes as decoded. HID Generic Desktop Y and Ry (and a Z/Rz layout's right-stick Rz) put
  /// the logical minimum up, so the decoded value is already Y down. An element carries one axis,
  /// so each keeps its pair's other.
  private var leftX: Float = 0
  private var leftY: Float = 0
  private var rightX: Float = 0
  private var rightY: Float = 0
  private let axisLayout: AxisLayout
  /// Whether the descriptor declares a Consumer Record button, which Xbox Series pads send as
  /// Share over Bluetooth.
  private let hasShareButton: Bool

  /// Creates a new HIDDescriptorDriver for the given device identifier.
  ///
  /// `reportDescriptor` is the bound interface's HID report descriptor, when observed. A
  /// descriptor with Z and Rz, a Brake or Accelerator, and no Rx or Ry selects the Z/Rz layout:
  /// Z/Rz is the right stick, Brake and Accelerator are the triggers, and buttons follow Linux
  /// hid-input's `BTN_GAMEPAD` order. The Xbox One S and Series Bluetooth descriptors in Linux
  /// mode (xpadneo `docs/descriptors/xb1s_linux.md`, `xbxs.md`) and the GameSir G7 SE
  /// (`incompat/gamesir_g7_se.md`) have that shape.
  public init(identifier: DeviceIdentifier, reportDescriptor: Data? = nil) {
    self.identifier = identifier
    let fields =
      reportDescriptor.flatMap { HIDReportDescriptorParser.parse(descriptor: Array($0))?.fields }
      ?? []
    let usages = Set(fields.map { HIDUsage(usagePage: $0.usagePage, usage: $0.usage) })
    hasShareButton = usages.contains(Self.usage(Self.consumerUsagePage, Self.usageRecord))
    if identifier.controllerIdentity.vendorID == Self.wr007VendorID
      && identifier.controllerIdentity.productID == Self.wr007ProductID
    {
      axisLayout = .wr007
    } else if identifier.controllerIdentity.vendorID == Self.envisionVendorID
      && identifier.controllerIdentity.productID == Self.envisionProductID
    {
      axisLayout = .envision
    } else if Self.zRzBrakeLeftDevices.contains([
      identifier.controllerIdentity.vendorID, identifier.controllerIdentity.productID,
    ]) {
      axisLayout = .zRzBrakeLeft
    } else if [identifier.controllerIdentity.vendorID, identifier.controllerIdentity.productID]
      == Self.dragonRiseDevice
    {
      axisLayout = .dragonRise
    } else if Self.hasZRzBrakeLeftShape(usages) {
      axisLayout = .zRzBrakeLeft
    } else {
      axisLayout = .standard
    }
    print("[HIDDescriptorDriver] Unrecognized controller \(identifier), using HID descriptors")
  }

  private static func usage(_ page: UInt32, _ usage: UInt32) -> HIDUsage {
    HIDUsage(usagePage: Int(page), usage: Int(usage))
  }

  private static func hasZRzBrakeLeftShape(_ usages: Set<HIDUsage>) -> Bool {
    let desktop = genericDesktopUsagePage
    let simulation = simulationControlsUsagePage
    return usages.isSuperset(of: [usage(desktop, usageZ), usage(desktop, usageRz)])
      && !usages.contains(usage(desktop, usageRx)) && !usages.contains(usage(desktop, usageRy))
      && (usages.contains(usage(simulation, usageBrake))
        || usages.contains(usage(simulation, usageAccelerator)))
  }

  /// A new transport session starts from neutral input.
  public func resetProtocolState() {
    state = .neutral
    (leftX, leftY, rightX, rightY) = (0, 0, 0, 0)
  }

  public var sessionPlan: DriverSessionPlan { DriverSessionPlan(parsesHIDElementValues: true) }
  public var outputCapabilities: PhysicalControllerOutputCapabilities { .none }
  public var defaultColor: ControllerColor? { nil }

  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  public var capabilities: ControllerCapabilities {
    guard axisLayout == .dragonRise else {
      return ControllerCapabilities(
        controls: ControlID.xboxLayout.union(hasShareButton ? [.guide, .share] : [.guide])
      )
    }
    return ControllerCapabilities(
      controls: ControlID.xboxLayout.subtracting([.leftTrigger, .rightTrigger]).union([
        .leftTriggerButton, .rightTriggerButton,
      ])
    )
  }

  /// Raw reports are handled through IOKit's descriptor-decoded element callback.
  public func parse(report _: Data, receivedAt _: MonotonicTimestamp) throws -> ControllerEvent? {
    nil
  }

  /// Folds one standard HID usage into the state, preserving paired stick coordinates.
  public func parse(
    elementValue value: HIDElementValue,
    receivedAt: MonotonicTimestamp
  ) -> ControllerEvent? {
    guard axisLayout != .envision || value.reportID == 6 else { return nil }
    var next = state
    let mapped: Bool
    switch value.usagePage {
    case Self.buttonUsagePage: mapped = foldButton(value, into: &next)
    case Self.genericDesktopUsagePage: mapped = foldGenericDesktop(value, into: &next)
    case Self.simulationControlsUsagePage: mapped = foldSimulationControl(value, into: &next)
    case Self.consumerUsagePage: mapped = foldConsumerControl(value, into: &next)
    default: mapped = false
    }
    guard mapped else { return nil }
    state = next
    return ControllerEvent(timestamp: receivedAt, state: next)
  }

  private func foldButton(_ value: HIDElementValue, into next: inout ControllerState) -> Bool {
    guard axisLayout != .envision || value.usage <= 10 else { return false }
    guard let control = control(for: value.usage) else { return false }
    next.set(control, pressed: value.integerValue != 0)
    return true
  }

  private func foldGenericDesktop(
    _ value: HIDElementValue,
    into next: inout ControllerState
  ) -> Bool {
    let usage = axisLayout == .envision ? Self.envisionAxisUsage(value.usage) : value.usage
    switch usage {
    case Self.usageX: leftX = Self.normalizedAxis(value)
    case Self.usageY: leftY = Self.normalizedAxis(value)
    case Self.usageZ:
      guard axisLayout.zRzIsRightStick else {
        next.leftTrigger = UnipolarValue(normalized: Self.normalizedTrigger(value))
        return true
      }
      rightX = Self.normalizedAxis(value)
    case Self.usageRx: rightX = Self.normalizedAxis(value)
    case Self.usageRy: rightY = Self.normalizedAxis(value)
    case Self.usageRz:
      guard axisLayout.zRzIsRightStick else {
        next.rightTrigger = UnipolarValue(normalized: Self.normalizedTrigger(value))
        return true
      }
      rightY = Self.normalizedAxis(value)
    case Self.usageHatSwitch:
      next.hat = Self.hatDirection(value)
      return true
    case Self.usageSystemMainMenu:
      // Xbox One S Bluetooth in Windows mode sends Guide here, in report 2.
      next.set(.guide, pressed: value.integerValue != 0)
      return true
    default: return false
    }
    next.leftStick = StickPosition(x: leftX, yDown: leftY)
    next.rightStick = StickPosition(x: rightX, yDown: rightY)
    return true
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

  private func foldSimulationControl(
    _ value: HIDElementValue,
    into next: inout ControllerState
  ) -> Bool {
    guard axisLayout.zRzIsRightStick, axisLayout != .dragonRise else { return false }
    let trigger = UnipolarValue(normalized: Self.normalizedTrigger(value))
    let brakeIsLeft = axisLayout == .zRzBrakeLeft
    switch value.usage {
    case Self.usageAccelerator:
      if brakeIsLeft { next.rightTrigger = trigger } else { next.leftTrigger = trigger }
    case Self.usageBrake:
      if brakeIsLeft { next.leftTrigger = trigger } else { next.rightTrigger = trigger }
    default: return false
    }
    return true
  }

  /// Xbox Bluetooth pads in Linux mode send View as AC Back (One S) and Share as Record
  /// (Series) in report 1, and Guide as AC Home in report 2 (xpadneo `docs/descriptors`).
  private func foldConsumerControl(
    _ value: HIDElementValue,
    into next: inout ControllerState
  ) -> Bool {
    let control: ControlID
    switch value.usage {
    case Self.usageACBack: control = .view
    case Self.usageACHome: control = .guide
    case Self.usageRecord: control = .share
    default: return false
    }
    next.set(control, pressed: value.integerValue != 0)
    return true
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

  private static func hatDirection(_ value: HIDElementValue) -> HatDirection {
    let position = value.integerValue - value.logicalMinimum
    guard position >= 0, position < 8 else { return .neutral }
    return [.north, .northEast, .east, .southEast, .south, .southWest, .west, .northWest][position]
  }

  private func control(for usage: UInt32) -> ControlID? {
    if axisLayout == .dragonRise {
      let dragonRise: [ControlID] = [
        .faceNorth, .faceEast, .faceSouth, .faceWest, .leftShoulder, .rightShoulder,
        .leftTriggerButton, .rightTriggerButton, .view, .menu, .leftStickClick, .rightStickClick,
      ]
      guard usage > 0, usage <= dragonRise.count else { return nil }
      return dragonRise[Int(usage - 1)]
    }
    if axisLayout.zRzIsRightStick {
      // Buttons 9 and 10 mirror the analog triggers.
      if axisLayout == .zRzBrakeLeft, usage == 13 { return .guide }
      return [
        1: .faceSouth, 2: .faceEast, 4: .faceWest, 5: .faceNorth, 7: .leftShoulder,
        8: .rightShoulder, 11: .view, 12: .menu, 14: .leftStickClick, 15: .rightStickClick,
      ][usage]
    }

    let standard: [ControlID] = [
      .faceSouth, .faceEast, .faceWest, .faceNorth, .leftShoulder, .rightShoulder, .view, .menu,
      .leftStickClick, .rightStickClick, .guide,
    ]
    guard usage > 0, usage <= standard.count else { return nil }
    return standard[Int(usage - 1)]
  }
}
