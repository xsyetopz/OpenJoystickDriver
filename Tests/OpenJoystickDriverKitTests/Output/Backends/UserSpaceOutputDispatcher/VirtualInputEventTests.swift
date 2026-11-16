import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct VirtualInputEventTests {
  /// Maps a parsed snapshot onto the virtual state with no stick dead zone.
  private func apply(
    _ event: ControllerEvent?,
    to state: inout VirtualGamepadState
  ) {
    guard let event else { return }
    VirtualGamepadReportMapping.apply(
      event.state,
      stickTransfer: .init(deadzone: 0, rescalesDeadzone: false),
      to: &state
    )
  }

  /// The `SDLCompatible` input report for `state`.
  private func xboxOneGIPReport(_ state: VirtualGamepadState) -> [UInt8] {
    XboxOneGIPHIDReportFormat().buildInputReport(from: state)
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
    apply(events, to: &state)
    let virtualReport = xboxOneGIPReport(state)

    #expect(events.contains(.press(.south)))
    #expect(events.contains(.press(.leftShoulder)))
    #expect(events.contains(.press(.guide)))
    #expect(events?.motion.count == 1)
    #expect(state.leftStickX > 32_000)
    #expect(state.leftStickY == -Int16.max)
    #expect(state.rightStickX == -Int16.max)
    #expect(state.rightStickY > 32_000)
    #expect(virtualReport[4] == 0x10)
    #expect(virtualReport[5] == 0x10)
    #expect(Array(virtualReport[6...7]) == [0xFF, 0x03])
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
    #expect(Array(xboxOneGIPReport(state)[6...9]) == [0xFF, 0x03, 0xFF, 0x03])
    packet[3] = 0
    packet[5] = 0
    apply(try parser.parseReport(Data(packet)), to: &state)
    #expect(state.leftTriggerPressed == false)
    #expect(state.rightTriggerPressed == false)
    #expect(Array(xboxOneGIPReport(state)[6...9]) == [0, 0, 0, 0])
  }

  @Test
  func digitalTriggerTransitionsDoNotReplaceAnalogPressure() {
    var state = VirtualGamepadState()
    var input = snapshot(.leftTrigger(0.5), .press(.leftTrigger))
    apply(ControllerEvent(timestamp: MonotonicTimestamp(nanoseconds: 0), state: input), to: &state)
    #expect(state.leftTrigger == 16_383)
    #expect(state.effectiveLeftTrigger == 16_383)
    input = input.applying([.release(.leftTrigger)])
    apply(ControllerEvent(timestamp: MonotonicTimestamp(nanoseconds: 0), state: input), to: &state)
    #expect(state.effectiveLeftTrigger == 16_383)
    input = input.applying([.leftTrigger(0)])
    apply(ControllerEvent(timestamp: MonotonicTimestamp(nanoseconds: 0), state: input), to: &state)
    #expect(state.effectiveLeftTrigger == 0)
  }

  /// Without a profile the virtual sticks follow the controller; dead zones belong to the profile
  /// and the game.
  @Test
  func unprofiledSticksReachVirtualReportWithoutDeadZone() {
    let zd = LogicalControllerID(vendorID: 0x413D, productID: 0x2104)
    for (x, y) in [(Float(0.12), Float(0.12)), (0.14, 0)] {
      var state = VirtualGamepadState()
      VirtualGamepadReportMapping.apply(
        snapshot(.leftStick(x: x, y: y)),
        stickTransfer: VirtualGamepadReportMapping.stickTransfer(for: zd),
        to: &state
      )
      #expect(abs(Int(state.leftStickX) - Int(x * 32_767)) <= 1)
      #expect(abs(Int(state.leftStickY) - Int(y * 32_767)) <= 1)
    }
  }

  /// A record's `tuning.stickDeadzone` reaches the dispatcher as a rescaling dead zone.
  @Test
  func recordTuningSetsStickDeadZone() {
    let tuned = LogicalControllerID(vendorID: 0x11C1, productID: 0x5600)
    #expect(
      VirtualGamepadReportMapping.stickTransfer(for: tuned)
        == .init(deadzone: 0.02, rescalesDeadzone: true)
    )
  }

  /// `stickDeadzone` is radial: a diagonal past it keeps both axes, a small cross-axis component
  /// of a deflected stick survives, and a stick inside it reads zero.
  @Test
  func recordStickDeadZoneIsRadial() {
    let transfer = VirtualGamepadReportMapping.StickTransfer(deadzone: 0.1, rescalesDeadzone: true)
    func mapped(_ x: Float, _ y: Float) -> (Int16, Int16) {
      var state = VirtualGamepadState()
      VirtualGamepadReportMapping.apply(
        snapshot(.leftStick(x: x, y: y)),
        stickTransfer: transfer,
        to: &state
      )
      return (state.leftStickX, state.leftStickY)
    }
    let diagonal = mapped(0.09, 0.09)
    #expect(diagonal.0 > 0 && diagonal.1 > 0)
    #expect(mapped(0.8, 0.05).1 > 0)
    #expect(mapped(0.07, 0.07) == (0, 0))
    #expect(abs(Int(mapped(1, 0).0) - 32_767) <= 1)
  }

  @Test
  func xidSoutheastSurvivesParserToReport() throws {
    var packet = [UInt8](repeating: 0, count: 20)
    packet[1] = 20
    packet[2] = 10
    var state = VirtualGamepadState()
    let parser = xidDriver()
    apply(try parser.parseReport(Data(packet)), to: &state)
    #expect(xboxOneGIPReport(state)[5] & 0x0F == 0x0A)
    packet[2] = 0
    apply(try parser.parseReport(Data(packet)), to: &state)
    #expect(xboxOneGIPReport(state)[5] & 0x0F == 0)
  }
}
