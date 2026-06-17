import Foundation
import IOKit
import IOKit.hid

extension DextOutputDispatcher {
  // MARK: - Event application (called inside reportLock.withLock)

  func applyEvent(_ event: ControllerEvent, deadzone: Float) {
    switch event {
    case .buttonPressed(let btn): if let bit = buttonBit(for: btn) { buttons |= (1 << bit) }
    case .buttonReleased(let btn): if let bit = buttonBit(for: btn) { buttons &= ~(1 << bit) }
    case .leftStickChanged(let x, let y):
      leftStickX = axisValue(x, deadzone: deadzone)
      leftStickY = axisValue(y, deadzone: deadzone)
    case .rightStickChanged(let x, let y):
      rightStickX = axisValue(x, deadzone: deadzone)
      rightStickY = axisValue(y, deadzone: deadzone)
    case .leftTriggerChanged(let v): leftTrigger = Int16(v.clamped(to: 0...1) * 32_767)
    case .rightTriggerChanged(let v): rightTrigger = Int16(v.clamped(to: 0...1) * 32_767)
    case .dpadChanged(let dir):
      hat = hatValue(for: dir)
      // Dual encode: set D-pad button bits 11–14 alongside the hat switch.
      let dpadMask: UInt32 = 0xF << 11  // bits 11-14
      buttons = (buttons & ~dpadMask) | GamepadHIDDescriptor.dpadButtonBits(for: hat)
    }
  }

  // MARK: - Report construction (called inside reportLock.withLock)

  func primaryOutputReport() -> (CFIndex, [UInt8]) {
    let reportID: CFIndex = {
      if let rid = format.inputReportID, rid != 0 { return CFIndex(rid) }
      return 0
    }()
    return (reportID, buildPrimaryReportPayload())
  }

  func buildPrimaryReportPayload() -> [UInt8] {
    let state = VirtualGamepadState(
      buttons: buttons,
      leftStickX: leftStickX,
      leftStickY: leftStickY,
      rightStickX: rightStickX,
      rightStickY: rightStickY,
      leftTrigger: leftTrigger,
      rightTrigger: rightTrigger,
      hat: hat
    )

    // IOHIDDeviceSetReport does not take a report-id byte in the buffer; report IDs
    // are encoded by the reportID argument. Our dext parses output report bytes and
    // relays them as input with Report ID 1.
    let full = format.buildInputReport(from: state)
    if let rid = format.inputReportID, rid != 0, full.first == rid {
      return Array(full.dropFirst())
    }
    return full
  }

  func xboxGuideReport(for event: ControllerEvent) -> (CFIndex, [UInt8])? {
    switch event {
    case .buttonPressed(let button) where button == .guide || button == .ps:
      return framedInputReport(reportID: 2, payload: [0x01])
    case .buttonReleased(let button) where button == .guide || button == .ps:
      return framedInputReport(reportID: 2, payload: [0x00])
    default: return nil
    }
  }

  func framedInputReport(reportID: UInt8, payload: [UInt8]) -> (CFIndex, [UInt8]) {
    (1, Self.relayMagic + [reportID] + payload)
  }

  // MARK: - Button mapping (XInputHID order)

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
    case .guide, .ps: return 10
    case .dpadUp: return 11
    case .dpadDown: return 12
    case .dpadLeft: return 13
    case .dpadRight: return 14
    case .share: return 15
    case .l2Digital, .r2Digital: return nil  // triggers are analog only in XInputHID
    case .touchpad: return nil
    case .genericButton1, .genericButton2: return nil
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
