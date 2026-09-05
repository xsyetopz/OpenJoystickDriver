import Foundation

extension UserSpaceOutputDispatcher {
  struct StickTransfer: Equatable, Sendable {
    let deadzone: Float
    let rescalesDeadzone: Bool
  }

  static func stickTransfer(for identifier: DeviceIdentifier) -> StickTransfer {
    if identifier.vendorID == 0x11C1 && identifier.productID == 0x5600 {
      return StickTransfer(deadzone: 0.02, rescalesDeadzone: true)
    }
    return StickTransfer(deadzone: 0.15, rescalesDeadzone: false)
  }

  // MARK: - Event application (called inside reportLock.withLock)

  func applyEvent(
    _ event: ControllerEvent,
    stickTransfer: StickTransfer,
    state: inout VirtualGamepadState
  ) {
    switch event {
    case .buttonPressed(let btn): if let bit = buttonBit(for: btn) { state.buttons |= (1 << bit) }
    case .buttonReleased(let btn): if let bit = buttonBit(for: btn) { state.buttons &= ~(1 << bit) }
    case .leftStickChanged(let x, let y):
      state.leftStickX = Self.axisValue(x, transfer: stickTransfer)
      state.leftStickY = Self.axisValue(y, transfer: stickTransfer)
    case .rightStickChanged(let x, let y):
      state.rightStickX = Self.axisValue(x, transfer: stickTransfer)
      state.rightStickY = Self.axisValue(y, transfer: stickTransfer)
    case .leftTriggerChanged(let v): state.leftTrigger = Int16(v.clamped(to: 0...1) * 32_767)
    case .rightTriggerChanged(let v): state.rightTrigger = Int16(v.clamped(to: 0...1) * 32_767)
    case .dpadChanged(let dir):
      state.hat = hatValue(for: dir)
      let dpadMask: UInt32 = 0xF << 11
      state.buttons =
        (state.buttons & ~dpadMask) | GamepadHIDDescriptor.dpadButtonBits(for: state.hat)
    }
  }

  func xboxGuideReport(for event: ControllerEvent) -> [UInt8]? { Self.xboxGuideReport(for: event) }

  static func xboxGuideReport(for event: ControllerEvent) -> [UInt8]? {
    switch event {
    case .buttonPressed(let button) where button == .guide || button == .ps: return [0x02, 0x01]
    case .buttonReleased(let button) where button == .guide || button == .ps: return [0x02, 0x00]
    default: return nil
    }
  }

  // MARK: - Button mapping (XInput semantic order)

  func buttonBit(for button: Button) -> UInt32? {
    switch button {
    case .a, .cross: return 0
    case .b, .circle: return 1
    case .x, .square: return 2
    case .y, .triangle: return 3
    case .leftBumper, .l1: return 4
    case .rightBumper, .r1: return 5
    case .leftStick: return 6
    case .rightStick: return 7
    case .start, .options: return 8
    case .back: return 9
    case .guide, .ps: return emitsXboxGuideReport ? nil : 10
    case .dpadUp: return 11
    case .dpadDown: return 12
    case .dpadLeft: return 13
    case .dpadRight: return 14
    case .share: return 15
    case .l2Digital, .r2Digital, .touchpad, .mute: return nil
    }
  }

  // MARK: - Axis + hat helpers

  static func axisValue(_ v: Float, transfer: StickTransfer) -> Int16 {
    let clamped = v.clamped(to: -1...1)
    let magnitude = abs(clamped)
    guard magnitude > transfer.deadzone else { return 0 }
    guard transfer.rescalesDeadzone else { return Int16(clamped * 32_767) }
    let rescaled = (magnitude - transfer.deadzone) / (1 - transfer.deadzone)
    return Int16(copysignf(rescaled, clamped) * 32_767)
  }

  func hatValue(for direction: DpadDirection) -> GamepadHIDDescriptor.Hat {
    switch direction {
    case .neutral: return .neutral
    case .north: return .north
    case .northEast: return .northEast
    case .east: return .east
    case .southEast: return .southEast
    case .south: return .south
    case .southWest: return .southWest
    case .west: return .west
    case .northWest: return .northWest
    }
  }
}
