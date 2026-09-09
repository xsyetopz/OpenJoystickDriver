import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct VirtualInputEventTests {
  private func apply(_ events: [ControllerEvent], to state: inout VirtualGamepadState) {
    let dispatcher = UserSpaceOutputDispatcher { _ in
      throw UserSpaceOutputDispatcher.CreationError.createFailed
    }
    for event in events {
      dispatcher.applyEvent(
        event,
        stickTransfer: .init(deadzone: 0, rescalesDeadzone: false),
        state: &state
      )
    }
  }

  @Test
  func nintendoDigitalTriggersSurviveParserAndVirtualOutput() throws {
    let parser = SwitchProParser()
    var packet: [UInt8] = [0x30, 0, 0x91, 0, 0, 0, 0, 8, 128, 0, 8, 128]
    var state = VirtualGamepadState()
    apply(try parser.parse(data: Data(packet)), to: &state)
    packet[3] = 0x80
    packet[5] = 0x80
    apply(try parser.parse(data: Data(packet)), to: &state)
    #expect(state.leftTriggerPressed)
    #expect(state.rightTriggerPressed)
    let nintendo = SwitchProUSBHIDReportFormat().buildInputReport(from: state)
    #expect(nintendo[3] & 0x80 == 0x80)
    #expect(nintendo[5] & 0x80 == 0x80)
    let sony = DualSenseUSBHIDReportFormat().buildInputReport(from: state)
    #expect(sony[5] == 255)
    #expect(sony[6] == 255)
    let xbox = Xbox360MacHIDReportFormat().buildInputReport(from: state)
    #expect(xbox[4] == 255)
    #expect(xbox[5] == 255)
    packet[3] = 0
    packet[5] = 0
    apply(try parser.parse(data: Data(packet)), to: &state)
    #expect(state.leftTriggerPressed == false)
    #expect(state.rightTriggerPressed == false)
    #expect(DualSenseUSBHIDReportFormat().buildInputReport(from: state)[5...6] == [0, 0])
    #expect(Xbox360MacHIDReportFormat().buildInputReport(from: state)[4...5] == [0, 0])
  }

  @Test
  func sonyTouchpadAndMuteSurviveParserPressAndRelease() throws {
    let parser = DualSenseParser()
    var packet = [UInt8](repeating: 0, count: 64)
    packet[0] = 1
    for index in 1...4 { packet[index] = 128 }
    packet[8] = 8
    var state = VirtualGamepadState()
    apply(try parser.parse(data: Data(packet)), to: &state)
    packet[10] = 0x06
    apply(try parser.parse(data: Data(packet)), to: &state)
    #expect(state.touchpadPressed)
    #expect(state.mutePressed)
    #expect(DualSenseUSBHIDReportFormat().buildInputReport(from: state)[10] == 0x06)
    #expect(DualSenseUSBHIDReportFormat().buildInputReport(from: state)[33] == 0x80)
    #expect(DualSenseUSBHIDReportFormat().buildInputReport(from: state)[37] == 0x80)
    #expect(DualShock4USBHIDReportFormat().buildInputReport(from: state)[7] == 0x02)
    #expect(DualShock4USBHIDReportFormat().buildInputReport(from: state)[35] == 0x80)
    #expect(DualShock4USBHIDReportFormat().buildInputReport(from: state)[39] == 0x80)
    packet[10] = 0
    apply(try parser.parse(data: Data(packet)), to: &state)
    #expect(state.touchpadPressed == false)
    #expect(state.mutePressed == false)
    #expect(DualSenseUSBHIDReportFormat().buildInputReport(from: state)[10] == 0)
    #expect(DualShock4USBHIDReportFormat().buildInputReport(from: state)[7] == 0)
  }

  @Test
  func digitalTriggerTransitionsDoNotReplaceAnalogPressure() {
    var state = VirtualGamepadState()
    apply([.leftTriggerChanged(0.5), .buttonPressed(.l2Digital)], to: &state)
    #expect(state.leftTrigger == 16_383)
    #expect(state.effectiveLeftTrigger == 16_383)
    apply([.buttonReleased(.l2Digital)], to: &state)
    #expect(state.effectiveLeftTrigger == 16_383)
    apply([.leftTriggerChanged(0)], to: &state)
    #expect(state.effectiveLeftTrigger == 0)
  }

  @Test
  func xidSoutheastSurvivesParserToReport() throws {
    var packet = [UInt8](repeating: 0, count: 20)
    packet[1] = 20
    packet[2] = 10
    var state = VirtualGamepadState()
    let parser = XIDParser()
    apply(try parser.parse(data: Data(packet)), to: &state)
    #expect(DualSenseUSBHIDReportFormat().buildInputReport(from: state)[8] & 0x0F == 3)
    packet[2] = 0
    apply(try parser.parse(data: Data(packet)), to: &state)
    #expect(DualSenseUSBHIDReportFormat().buildInputReport(from: state)[8] & 0x0F == 8)
  }
}
