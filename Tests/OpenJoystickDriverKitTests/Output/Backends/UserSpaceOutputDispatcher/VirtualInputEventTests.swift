import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct VirtualInputEventTests {
  /// Maps a parsed snapshot onto the virtual state with no stick dead zone.
  private func apply(
    _ event: ControllerEvent?,
    labels: ControllerButtonLabels = .standard,
    to state: inout VirtualGamepadState
  ) {
    guard let event else { return }
    UserSpaceOutputDispatcher.apply(
      event.state,
      labels: labels,
      stickTransfer: .init(deadzone: 0, rescalesDeadzone: false),
      to: &state
    )
  }

  /// The `hid-xbox-one-s-bt` input report for `state`.
  private func xboxOneSReport(_ state: VirtualGamepadState) throws -> [UInt8] {
    try XboxGeckoHIDReportFormat().buildInputReport(from: state)
  }

  @Test(arguments: [false, true])
  func ds4USBAndBluetoothFixturesReachVirtualReports(bluetooth: Bool) throws {
    let parser = DualShock4Driver(prefersBluetooth: bluetooth)
    var packet = [UInt8](repeating: 0, count: bluetooth ? 78 : 64)
    let base = bluetooth ? 3 : 1
    packet[0] = bluetooth ? 0x11 : 0x01
    if bluetooth {
      packet[1] = 0xC0
      packet[2] = 0
    }
    packet[base] = 255
    packet[base + 1] = 0
    packet[base + 2] = 0
    packet[base + 3] = 255
    packet[base + 4] = 0x28
    packet[base + 5] = 0x01
    packet[base + 6] = 0x01
    packet[base + 7] = 255
    packet[base + 8] = 128
    packet[base + 12] = 1
    packet[base + 18] = 2
    packet[base + 29] = bluetooth ? 0x19 : 0x09
    if bluetooth { applyDS4BluetoothInputCRC(to: &packet) }

    let events = try parser.parseReport(Data(packet))
    var state = VirtualGamepadState()
    apply(events, labels: .playStation, to: &state)
    let virtualReport = try xboxOneSReport(state)

    #expect(events.contains(.press(.faceSouth)))
    #expect(events.contains(.press(.leftShoulder)))
    #expect(events.contains(.press(.guide)))
    #expect(events?.motion.count == 1)
    #expect(state.leftStickX > 32_000)
    #expect(state.leftStickY == -Int16.max)
    #expect(state.rightStickX == -Int16.max)
    #expect(state.rightStickY > 32_000)
    #expect(virtualReport[14] == 0x11)
    #expect(virtualReport[15] == 0x04)
    #expect(Array(virtualReport[9...10]) == [0xFF, 0x03])
    #expect(virtualReport[13] == 0)
    #expect(
      parser.power
        == ControllerConnectionState.Power(
          charging: bluetooth ? .charging : .discharging,
          battery: BatteryLevel(percentage: 90...99),
          wiredPower: bluetooth
        )
    )
  }

  @Test
  func nintendoDigitalTriggersSurviveParserAndVirtualOutput() throws {
    let parser = Switch1Driver()
    var packet: [UInt8] = [0x30, 0, 0x91, 0, 0, 0, 0, 8, 128, 0, 8, 128]
    var state = VirtualGamepadState()
    apply(try parser.parseReport(Data(packet)), to: &state)
    packet[3] = 0x80
    packet[5] = 0x80
    apply(try parser.parseReport(Data(packet)), to: &state)
    #expect(state.leftTriggerPressed)
    #expect(state.rightTriggerPressed)
    #expect(Array(try xboxOneSReport(state)[9...12]) == [0xFF, 0x03, 0xFF, 0x03])
    packet[3] = 0
    packet[5] = 0
    apply(try parser.parseReport(Data(packet)), to: &state)
    #expect(state.leftTriggerPressed == false)
    #expect(state.rightTriggerPressed == false)
    #expect(Array(try xboxOneSReport(state)[9...12]) == [0, 0, 0, 0])
  }

  @Test
  func digitalTriggerTransitionsDoNotReplaceAnalogPressure() {
    var state = VirtualGamepadState()
    var input = snapshot(.leftTrigger(0.5), .press(.leftTriggerButton))
    apply(ControllerEvent(timestamp: MonotonicTimestamp(nanoseconds: 0), state: input), to: &state)
    #expect(state.leftTrigger == 16_383)
    #expect(state.effectiveLeftTrigger == 16_383)
    input = input.applying([.release(.leftTriggerButton)])
    apply(ControllerEvent(timestamp: MonotonicTimestamp(nanoseconds: 0), state: input), to: &state)
    #expect(state.effectiveLeftTrigger == 16_383)
    input = input.applying([.leftTrigger(0)])
    apply(ControllerEvent(timestamp: MonotonicTimestamp(nanoseconds: 0), state: input), to: &state)
    #expect(state.effectiveLeftTrigger == 0)
  }

  /// Without a profile the virtual sticks follow the controller; dead zones belong to the profile
  /// and the game.
  @Test
  func unprofiledSticksReachTheVirtualReportWithoutADeadZone() {
    let zd = DeviceIdentifier(vendorID: 0x413D, productID: 0x2104)
    for (x, y) in [(Float(0.12), Float(0.12)), (0.14, 0)] {
      var state = VirtualGamepadState()
      UserSpaceOutputDispatcher.apply(
        snapshot(.leftStick(x: x, y: y)),
        labels: .standard,
        stickTransfer: UserSpaceOutputDispatcher.stickTransfer(for: zd),
        to: &state
      )
      #expect(abs(Int(state.leftStickX) - Int(x * 32_767)) <= 1)
      #expect(abs(Int(state.leftStickY) - Int(y * 32_767)) <= 1)
    }
  }

  @Test
  func xidSoutheastSurvivesParserToReport() throws {
    var packet = [UInt8](repeating: 0, count: 20)
    packet[1] = 20
    packet[2] = 10
    var state = VirtualGamepadState()
    let parser = XIDDriver()
    apply(try parser.parseReport(Data(packet)), to: &state)
    #expect(try xboxOneSReport(state)[13] == 0x04)
    packet[2] = 0
    apply(try parser.parseReport(Data(packet)), to: &state)
    #expect(try xboxOneSReport(state)[13] == 0)
  }
}
