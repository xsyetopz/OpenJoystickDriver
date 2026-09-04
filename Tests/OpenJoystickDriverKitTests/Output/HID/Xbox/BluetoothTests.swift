import Testing

@testable import OpenJoystickDriverKit

struct XboxOneHIDReportFormatTests {
  private func format() throws -> HIDDescriptorReportFormat {
    try HIDDescriptorReportFormat(
      descriptor: XboxOneBluetoothHIDDescriptor.seriesDescriptor,
      buttonUsageMap: XboxOneBluetoothHIDDescriptor.buttonUsageMap,
      digitalUsageMap: XboxOneBluetoothHIDDescriptor.seriesDigitalUsageMap
    )
  }

  private func report(buttonBit: Int) throws -> [UInt8] {
    try format().buildInputReport(from: VirtualGamepadState(buttons: 1 << UInt32(buttonBit)))
  }
  @Test func testMapsFaceAndShoulderButtonsDirectly() throws {
    let a = try report(buttonBit: 0)
    let rb = try report(buttonBit: 5)

    #expect(a.count == 17)
    #expect(a[0] == 1)
    #expect(a[14] == 0x01)
    #expect(rb[14] == 0x20)
  }
  @Test func testParsesAndPacksPrimaryAxes() throws {
    let full = try format().buildInputReport(
      from: VirtualGamepadState(
        leftStickX: 32_767,
        leftStickY: 16_384,
        rightStickX: -32_767,
        rightStickY: -16_384,
        leftTrigger: 32_767,
        rightTrigger: 16_384
      )
    )

    #expect(full[0] == 1)
    #expect(full[1] == 0xFF)
    #expect(full[2] == 0xFF)
    #expect(full[3] == 0xFF)
    #expect(full[4] == 0xBF)
    #expect(full[5] == 0x00)
    #expect(full[6] == 0x00)
    #expect(full[7] == 0xFF)
    #expect(full[8] == 0x3F)
    #expect(full[9] == 0xFF)
    #expect(full[10] == 0x03)
    #expect(full[11] == 0xFF)
    #expect(full[12] == 0x01)
    #expect(full[13] == 0x00)
    #expect(full[14] == 0x00)
  }
  @Test func testMapsAppleGameControllerButtonsOneAtATime() throws {
    let neutral = try format().buildInputReport(from: VirtualGamepadState())
    let cases: [(bit: GamepadHIDDescriptor.ButtonBit, reportByte: Int, mask: UInt8)] = [
      (.back, 14, 0x40), (.start, 14, 0x80), (.leftStick, 15, 0x01), (.rightStick, 15, 0x02),
      (.guide, 15, 0x04)
    ]

    for testCase in cases {
      let report = try report(buttonBit: testCase.bit.rawValue)

      #expect(report[testCase.reportByte] == testCase.mask)
      #expect(
        report.enumerated().allSatisfy { index, value in
          index == testCase.reportByte || value == neutral[index]
        }
      )
    }
  }
  @Test func testPreservesPrimaryButtonCountAndGuideMapping() throws {
    let parsed = try #require(
      HIDReportDescriptorParser.parse(descriptor: XboxOneBluetoothHIDDescriptor.seriesDescriptor)
    )
    let buttonUsages = parsed.fields.filter { $0.reportID == 1 && $0.usagePage == 0x09 }.sorted {
      $0.bitOffset < $1.bitOffset
    }.map(\.usage)

    #expect(buttonUsages == Array(1...15))
    #expect(XboxOneBluetoothHIDDescriptor.buttonUsageMap[9] == 7)
    #expect(XboxOneBluetoothHIDDescriptor.buttonUsageMap[8] == 8)
    #expect(XboxOneBluetoothHIDDescriptor.buttonUsageMap[6] == 9)
    #expect(XboxOneBluetoothHIDDescriptor.buttonUsageMap[7] == 10)
    #expect(XboxOneBluetoothHIDDescriptor.buttonUsageMap[10] == 11)
    #expect(parsed.fields.contains { $0.reportID == 2 && $0.usagePage == 0x01 && $0.usage == 0x85 })
    #expect(parsed.fields.contains { $0.reportID == 1 && $0.usagePage == 0x0C && $0.usage == 0xB2 })
    #expect(buttonUsages.count == 15)
  }
  @Test func testMapsShareIndependentlyFromView() throws {
    let neutral = try format().buildInputReport(from: VirtualGamepadState())
    let view = try report(buttonBit: GamepadHIDDescriptor.ButtonBit.back.rawValue)
    let share = try report(buttonBit: GamepadHIDDescriptor.ButtonBit.share.rawValue)

    #expect(view[14] == 0x40)
    #expect(view[16] == 0x00)
    #expect(share[14] == 0x00)
    #expect(share[16] == 0x01)
    #expect(
      share.enumerated().allSatisfy { index, value in index == 16 || value == neutral[index] }
    )
  }
  @Test func testPacksDpadAsHatSwitch() throws {
    let north = try format().buildInputReport(from: VirtualGamepadState(hat: .north))
    let east = try format().buildInputReport(from: VirtualGamepadState(hat: .east))
    let neutral = try format().buildInputReport(from: VirtualGamepadState(hat: .neutral))

    #expect(north[13] == 0x01)
    #expect(east[13] == 0x03)
    #expect(neutral[13] == 0x00)
  }
  @Test func testPacksDpadAsDigitalButtons() throws {
    let north = try format().buildInputReport(
      from: VirtualGamepadState(buttons: GamepadHIDDescriptor.dpadButtonBits(for: .north))
    )
    let east = try format().buildInputReport(
      from: VirtualGamepadState(buttons: GamepadHIDDescriptor.dpadButtonBits(for: .east))
    )

    #expect(north[15] == 0x08)
    #expect(east[15] == 0x40)
  }
}
