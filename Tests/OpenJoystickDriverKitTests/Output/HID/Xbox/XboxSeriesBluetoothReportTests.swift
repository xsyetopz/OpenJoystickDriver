import Testing

@testable import OpenJoystickDriverKit

struct XboxSeriesBluetoothHIDReportFormatTests {
  private let format = XboxSeriesBluetoothHIDReportFormat()

  /// Report 1 at rest: sticks at the unsigned centre `0x8000`, triggers, hat, buttons and Share
  /// clear.
  private static let neutral: [UInt8] = [
    1, 0, 128, 0, 128, 0, 128, 0, 128, 0, 0, 0, 0, 0, 0, 0, 0,
  ]

  private func report(buttonBit: GamepadHIDDescriptor.ButtonBit) -> [UInt8] {
    format.buildInputReport(from: VirtualGamepadState(buttons: 1 << UInt32(buttonBit.rawValue)))
  }

  @Test
  func neutralReportIsSeventeenBytesWithCentredSticks() {
    #expect(format.buildInputReport(from: VirtualGamepadState()) == Self.neutral)
    #expect(format.inputReportID == 1)
    #expect(format.outputReportID == 3)
    #expect(format.outputReportPayloadSize == 8)
  }

  @Test
  func everyDigitalControlSetsOnlyItsBit() {
    let controls: [(GamepadHIDDescriptor.ButtonBit, Int, UInt8)] = [
      (.a, 14, 0x01), (.b, 14, 0x02), (.x, 14, 0x08), (.y, 14, 0x10), (.leftBumper, 14, 0x40),
      (.rightBumper, 14, 0x80), (.back, 15, 0x04), (.start, 15, 0x08), (.leftStick, 15, 0x20),
      (.rightStick, 15, 0x40), (.share, 16, 0x01),
    ]
    for (button, byte, mask) in controls {
      let value = report(buttonBit: button)
      #expect(value[byte] == mask)
      #expect(
        value.enumerated().allSatisfy { $0.offset == byte || $0.element == Self.neutral[$0.offset] }
      )
    }
  }

  @Test
  func theDpadTravelsOnlyInTheHat() {
    for button in [GamepadHIDDescriptor.ButtonBit.dpadUp, .dpadDown, .dpadLeft, .dpadRight] {
      #expect(report(buttonBit: button) == Self.neutral)
    }
  }

  @Test
  func guideTravelsOnButtonThirteenAndInReportTwo() {
    let guide = VirtualGamepadState(
      buttons: 1 << UInt32(GamepadHIDDescriptor.ButtonBit.guide.rawValue)
    )
    var expected = Self.neutral
    expected[15] = 0x10
    #expect(format.buildInputReport(from: guide) == expected)
    #expect(format.buildAuxiliaryInputReports(from: guide) == [[2, 1]])
    #expect(format.buildAuxiliaryInputReports(from: VirtualGamepadState()) == [[2, 0]])
  }

  @Test
  func sticksAndTriggersPackIntoTheirFields() {
    let full = format.buildInputReport(
      from: VirtualGamepadState(
        leftStickX: 32_767,
        leftStickY: 16_384,
        rightStickX: -32_767,
        rightStickY: -16_384,
        leftTrigger: 32_767,
        rightTrigger: 16_384
      )
    )
    #expect(
      Array(full[1...12]) == [
        0xFF, 0xFF, 0x00, 0xC0, 0x01, 0x00, 0x00, 0x40, 0xFF, 0x03, 0xFF, 0x01,
      ]
    )
  }

  @Test
  func theHatCarriesTheDpad() {
    #expect(format.buildInputReport(from: VirtualGamepadState(hat: .north))[13] == 0x01)
    #expect(format.buildInputReport(from: VirtualGamepadState(hat: .east))[13] == 0x03)
    #expect(format.buildInputReport(from: VirtualGamepadState(hat: .neutral))[13] == 0x00)
  }

  @Test
  func theDescriptorHasFifteenButtonsShareAndTheRumbleReport() throws {
    let parsed = try #require(
      HIDReportDescriptorParser.parse(descriptor: XboxSeriesBluetoothHIDDescriptor.descriptor)
    )
    let buttons = parsed.fields.filter { $0.reportID == 1 && $0.usagePage == 0x09 }
      .sorted { $0.bitOffset < $1.bitOffset }.map(\.usage)
    #expect(buttons == Array(1...15))
    let axes = parsed.fields.filter { $0.reportID == 1 && $0.usagePage != 0x09 && $0.bitSize >= 10 }
      .sorted { $0.bitOffset < $1.bitOffset }.map { [$0.usagePage, $0.usage] }
    #expect(
      axes == [
        [0x01, 0x30], [0x01, 0x31], [0x01, 0x32], [0x01, 0x35], [0x02, 0xC5], [0x02, 0xC4],
      ]
    )
    #expect(parsed.fields.contains { $0.reportID == 1 && $0.usagePage == 0x0C && $0.usage == 0xB2 })
    #expect(parsed.payloadSizeBytesByReportID[1] == 16)
    #expect(parsed.fields.contains { $0.reportID == 2 && $0.usagePage == 0x01 && $0.usage == 0x85 })
    #expect(parsed.payloadSizeBytesByReportID[2] == 1)
  }

  @Test
  func thePersonaPublishesTheXboxSeriesBluetoothIdentity() {
    let profile = VirtualHIDProfileID.gameControllerCompatible.makeProfile()
    #expect(profile.identity.vendorID == 0x045E)
    #expect(profile.identity.productID == 0x0B13)
    #expect(profile.identity.productName == "Xbox Wireless Controller")
    #expect(profile.identity.transport == "Bluetooth")
    #expect(profile.descriptor == XboxSeriesBluetoothHIDDescriptor.descriptor)
    #expect(VirtualHIDProfileID.gameControllerCompatible.worksWithDefaultSDLHints == false)
    #expect(
      VirtualHIDProfileID.gameControllerCompatible.commandLineName == "game-controller-compatible"
    )
  }
}
