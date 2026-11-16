import Testing

@testable import OpenJoystickDriverKit

/// The layout of the descriptor that the macOS Xbox 360 driver publishes.
///
/// Recorded from a NITHO MLT-KRMA-K on its 2.4 GHz receiver (`045E:028E`): each control pressed in
/// turn set the report bit that the descriptor names for the usage below.
struct MacOSXbox360DescriptorLayoutTests {
  private let parser = HIDDescriptorDriver(
    model: ControllerModelID(vendorID: 0x045E, productID: 0x028E),
    reportDescriptor: RecordedHIDDescriptors.macOSXbox360
  )

  private func parse(_ elementValue: HIDElementValue) -> ControllerEvent? {
    parser.parse(elementValue: elementValue, receivedAt: MonotonicTimestamp(nanoseconds: 0))
  }

  @Test
  func mapsRecordedButtonsAndDpad() {
    let buttons: [UInt32: Control] = [
      1: .south, 2: .east, 3: .west, 4: .north, 5: .leftShoulder, 6: .rightShoulder,
      7: .leftStickClick, 8: .rightStickClick, 9: .start, 10: .back, 11: .guide,
    ]
    for (usage, control) in buttons {
      #expect(parse(value(page: 9, usage: usage, integer: 1)).contains(.press(control)))
      #expect(parse(value(page: 9, usage: usage, integer: 0)).contains(.release(control)))
    }
    let dpad: [UInt32: HatDirection] = [12: .north, 13: .south, 14: .west, 15: .east]
    for (usage, direction) in dpad {
      #expect(parse(value(page: 9, usage: usage, integer: 1)).contains(.hat(direction)))
      #expect(parse(value(page: 9, usage: usage, integer: 0)).contains(.hat(.neutral)))
    }
    #expect(parser.capabilities.controls.isSuperset(of: Set(buttons.values).union(Control.dpad)))
  }

  @Test
  func stickUpIsPositiveAndTriggersAreZAndRz() {
    #expect(parse(stick(usage: 0x31, 32767)).contains(.leftStick(x: 0, y: -1)))
    #expect(parse(stick(usage: 0x34, -32768)).contains(.rightStick(x: 0, y: 1)))
    #expect(parse(value(usage: 0x32, integer: 255)).contains(.leftTrigger(1)))
    #expect(parse(value(usage: 0x35, integer: 255)).contains(.rightTrigger(1)))
  }

  private func stick(usage: UInt32, _ integer: Int) -> HIDElementValue {
    HIDElementValue(
      usagePage: 1,
      usage: usage,
      logicalMinimum: -32768,
      logicalMaximum: 32767,
      integerValue: integer,
      reportID: 0
    )
  }

  private func value(page: UInt32 = 1, usage: UInt32, integer: Int) -> HIDElementValue {
    HIDElementValue(
      usagePage: page,
      usage: usage,
      logicalMinimum: 0,
      logicalMaximum: page == 9 ? 1 : 255,
      integerValue: integer,
      reportID: 0
    )
  }
}
