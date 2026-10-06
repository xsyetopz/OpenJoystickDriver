import OpenJoystickDriverKit
import Testing

struct SCUFEnvisionParserTests {
  private func parse(
    _ parser: HIDDescriptorDriver,
    _ elementValue: HIDElementValue
  ) -> ControllerEvent? {
    parser.parse(elementValue: elementValue, receivedAt: MonotonicTimestamp(nanoseconds: 0))
  }

  private func parser() -> HIDDescriptorDriver {
    HIDDescriptorDriver(
      identifier: DeviceIdentifier(vendorID: 0x2E95, productID: 0x434D),
      quirks: [.scufEnvision]
    )
  }

  @Test
  func mapsConfirmedButtonsAndRejectsUnverifiedButtons() {
    let parser = parser()
    let buttons: [ControlID] = [
      .faceSouth, .faceEast, .faceWest, .faceNorth, .leftShoulder, .rightShoulder, .view, .menu,
      .leftStickClick, .rightStickClick,
    ]
    for (index, button) in buttons.enumerated() {
      #expect(
        parse(parser, value(page: 9, usage: UInt32(index + 1), integer: 1)).contains(.press(button))
      )
      #expect(
        parse(parser, value(page: 9, usage: UInt32(index + 1), integer: 0)).contains(
          .release(button)
        )
      )
    }
    for usage: UInt32 in 11...19 {
      #expect(parse(parser, value(page: 9, usage: usage, integer: 1)) == nil)
    }
  }

  @Test
  func acceptsOnlyReportSix() {
    let parser = parser()
    for reportID: UInt32? in [nil, 0, 1, 7, 256] {
      #expect(parse(parser, value(page: 9, usage: 1, integer: 1, reportID: reportID)) == nil)
    }
    #expect(
      parse(parser, value(page: 9, usage: 1, integer: 1, reportID: 6)).contains(.press(.faceSouth))
    )
  }

  @Test
  func mapsSignedSticksAndIndependentTriggers() {
    let parser = parser()
    #expect(parse(parser, value(usage: 0x30, integer: 32_767)).contains(.leftStick(x: 1, y: 0)))
    #expect(parse(parser, value(usage: 0x31, integer: -32_768)).contains(.leftStick(x: 1, y: -1)))
    #expect(parse(parser, value(usage: 0x32, integer: -32_768)).contains(.rightStick(x: -1, y: 0)))
    #expect(parse(parser, value(usage: 0x35, integer: 32_767)).contains(.rightStick(x: -1, y: 1)))
    #expect(
      parse(parser, value(usage: 0x33, integer: 1_023, minimum: 0, maximum: 1_023)).contains(
        .leftTrigger(1)
      )
    )
    #expect(
      parse(parser, value(usage: 0x34, integer: 512, minimum: 0, maximum: 1_023)).contains(
        .rightTrigger(Float(512) / 1_023)
      )
    )
  }

  @Test
  func mapsHatDiagonalsAndNeutral() {
    let parser = parser()
    let directions: [HatDirection] = [
      .north, .northEast, .east, .southEast, .south, .southWest, .west, .northWest, .neutral,
    ]
    for (position, direction) in directions.enumerated() {
      #expect(
        parse(parser, value(usage: 0x39, integer: position, minimum: 0, maximum: 7)).contains(
          .hat(direction)
        )
      )
    }
  }

  @Test
  func ordinaryGenericControllerStillUsesDescriptorDefaults() {
    let parser = HIDDescriptorDriver(identifier: DeviceIdentifier(vendorID: 1, productID: 2))
    #expect(
      parse(parser, value(usage: 0x32, integer: 255, minimum: 0, maximum: 255, reportID: nil))
        .contains(.leftTrigger(1))
    )
    #expect(
      parse(parser, value(page: 9, usage: 11, integer: 1, reportID: 99)).contains(.press(.guide))
    )
  }

  private func value(
    page: UInt32 = 1,
    usage: UInt32,
    integer: Int,
    minimum: Int = -32_768,
    maximum: Int = 32_767,
    reportID: UInt32? = 6
  ) -> HIDElementValue {
    HIDElementValue(
      usagePage: page,
      usage: usage,
      logicalMinimum: minimum,
      logicalMaximum: maximum,
      integerValue: integer,
      reportID: reportID
    )
  }
}
