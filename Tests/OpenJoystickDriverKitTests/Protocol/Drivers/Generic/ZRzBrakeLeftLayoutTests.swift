import Testing

@testable import OpenJoystickDriverKit

/// The Z/Rz right-stick layout with Brake as LT and a Home button.
///
/// Recorded from a wired GameSir G7 SE (firmware 6.6.4) in its HID mode, report 0x05: 15 buttons,
/// hat, X Y Z Rz and Simulation Brake then Accelerator, all 8-bit 0...255. The 8BitDo Ultimate 2C
/// Wireless over Bluetooth LE (`2DC8:301B`) was confirmed on hardware to use the same usages; its
/// wired DInput mode (`2DC8:301D`) is assumed to match. The GameSir is not listed by identity; its
/// recorded descriptor selects the layout.
struct ZRzBrakeLeftLayoutTests {
  static let models = [
    ControllerModelID(vendorID: 0x3537, productID: 0x1082),
    ControllerModelID(vendorID: 0x2DC8, productID: 0x301B),
    ControllerModelID(vendorID: 0x2DC8, productID: 0x301D),
  ]

  private func makeParser(_ model: ControllerModelID) throws -> HIDDescriptorDriver {
    let isGameSir = model.vendorID == 0x3537
    return HIDDescriptorDriver(
      model: model,
      reportDescriptor: isGameSir ? RecordedHIDDescriptors.gameSirG7SE : nil,
      usageMap: isGameSir ? nil : try catalogUsageMap(model.vendorID, model.productID)
    )
  }

  private func parse(
    _ parser: HIDDescriptorDriver,
    _ elementValue: HIDElementValue
  ) -> ControllerEvent? {
    parser.parse(elementValue: elementValue, receivedAt: MonotonicTimestamp(nanoseconds: 0))
  }

  @Test(arguments: models)
  func mapsRecordedButtonsAndIgnoresDigitalTriggerBits(model: ControllerModelID) throws {
    let parser = try makeParser(model)
    let buttons: [UInt32: Control] = [
      1: .south, 2: .east, 4: .west, 5: .north, 7: .leftShoulder, 8: .rightShoulder,
      11: .back, 12: .start, 13: .guide, 14: .leftStickClick, 15: .rightStickClick,
    ]
    for (usage, button) in buttons {
      #expect(parse(parser, value(page: 9, usage: usage, integer: 1)).contains(.press(button)))
      #expect(parse(parser, value(page: 9, usage: usage, integer: 0)).contains(.release(button)))
    }
    // Buttons 9 and 10 mirror LT and RT, whose analog values arrive on the Simulation page.
    for usage: UInt32 in [3, 6, 9, 10, 16] {
      #expect(parse(parser, value(page: 9, usage: usage, integer: 1)) == nil)
    }
  }

  @Test(arguments: models)
  func zAndRzAreTheRightStick(model: ControllerModelID) throws {
    let parser = try makeParser(model)
    #expect(parse(parser, value(usage: 0x32, integer: 255)).contains(.rightStick(x: 1, y: 0)))
    let down = parse(parser, value(usage: 0x35, integer: 255))
    #expect(down.contains(.rightStick(x: 1, y: 1)))
    #expect(down?.state.leftTrigger == UnipolarValue(normalized: 0))
    #expect(down?.state.rightTrigger == UnipolarValue(normalized: 0))
  }

  @Test(arguments: models)
  func brakeIsLeftTriggerAndAcceleratorIsRightTrigger(model: ControllerModelID) throws {
    let parser = try makeParser(model)
    #expect(parse(parser, value(page: 2, usage: 0xC5, integer: 255)).contains(.leftTrigger(1)))
    #expect(
      parse(parser, value(page: 2, usage: 0xC4, integer: 128)).contains(
        .rightTrigger(Float(128) / 255)
      )
    )
  }

  private func value(page: UInt32 = 1, usage: UInt32, integer: Int) -> HIDElementValue {
    HIDElementValue(
      usagePage: page,
      usage: usage,
      logicalMinimum: 0,
      logicalMaximum: page == 9 ? 1 : 255,
      integerValue: integer,
      reportID: 5
    )
  }
}
