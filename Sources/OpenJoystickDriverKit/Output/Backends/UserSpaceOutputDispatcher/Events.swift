import Foundation

extension UserSpaceOutputDispatcher {
  // MARK: - Event application (called inside reportLock.withLock)

  func applyEvent(_ event: ControllerEvent, deadzone: Float, state: inout VirtualGamepadState) {
    switch event {
    case .buttonPressed(let btn): if let bit = buttonBit(for: btn) { state.buttons |= (1 << bit) }
    case .buttonReleased(let btn): if let bit = buttonBit(for: btn) { state.buttons &= ~(1 << bit) }
    case .leftStickChanged(let x, let y):
      state.leftStickX = axisValue(x, deadzone: deadzone)
      state.leftStickY = axisValue(y, deadzone: deadzone)
    case .rightStickChanged(let x, let y):
      state.rightStickX = axisValue(x, deadzone: deadzone)
      state.rightStickY = axisValue(y, deadzone: deadzone)
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
    case .l2Digital, .r2Digital: return nil
    case .touchpad: return nil
    case .genericButton1: return 15
    case .genericButton2: return nil
    case .genericButton3, .genericButton4: return nil
    case .genericButton5, .genericButton6, .genericButton7, .genericButton8: return nil
    }
  }

  // MARK: - Axis + hat helpers

  func axisValue(_ v: Float, deadzone: Float) -> Int16 {
    let clamped = v.clamped(to: -1...1)
    guard abs(clamped) > deadzone else { return 0 }
    return Int16(clamped * 32_767)
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
