import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

struct XboxOneGIPHIDReportFormatTests {
  private let format = XboxOneGIPHIDReportFormat()

  private func report(buttonBit: GamepadHIDDescriptor.ButtonBit) -> [UInt8] {
    format.buildInputReport(from: VirtualGamepadState(buttons: 1 << UInt32(buttonBit.rawValue)))
  }

  /// Every byte but `index` equals the neutral report's.
  private func onlyByteDiffers(_ report: [UInt8], at index: Int) -> Bool {
    let neutral = ProtocolPacketFixtures.XboxOneGIP.neutralInputReport
    return report.enumerated().allSatisfy { $0.offset == index || $0.element == neutral[$0.offset] }
  }

  @Test
  func neutralReportIsAGIPInputPacket() {
    let neutral = format.buildInputReport(from: VirtualGamepadState())

    #expect(neutral == ProtocolPacketFixtures.XboxOneGIP.neutralInputReport)
    // Command 0x20, options 0x00, a sequence, then the length of the 14-byte payload.
    #expect(Array(neutral[0...3]) == [0x20, 0x00, 0x00, 14])
    #expect(neutral.count == 4 + 14)
  }

  @Test
  func everyButtonSetsItsGIPBit() {
    let controls: [(GamepadHIDDescriptor.ButtonBit, Int, UInt8)] = [
      (.start, 4, 0x04), (.back, 4, 0x08), (.a, 4, 0x10), (.b, 4, 0x20), (.x, 4, 0x40),
      (.y, 4, 0x80), (.leftBumper, 5, 0x10), (.rightBumper, 5, 0x20), (.leftStick, 5, 0x40),
      (.rightStick, 5, 0x80),
    ]
    for (button, byte, mask) in controls {
      let value = report(buttonBit: button)
      #expect(value[byte] == mask)
      #expect(onlyByteDiffers(value, at: byte))
    }
  }

  @Test
  func neverSetsShareAndStateDpadButtonsCarryNothing() {
    let neutral = ProtocolPacketFixtures.XboxOneGIP.neutralInputReport
    for button in [
      GamepadHIDDescriptor.ButtonBit.share, .dpadUp, .dpadDown, .dpadLeft, .dpadRight,
    ] {
      #expect(report(buttonBit: button) == neutral)
    }
  }

  @Test
  func hatSetsDpadBits() {
    let cases: [(GamepadHIDDescriptor.Hat, UInt8)] = [
      (.neutral, 0x00), (.north, 0x01), (.northEast, 0x09), (.east, 0x08), (.southEast, 0x0A),
      (.south, 0x02), (.southWest, 0x06), (.west, 0x04), (.northWest, 0x05),
    ]
    for (hat, bits) in cases {
      let value = format.buildInputReport(from: VirtualGamepadState(hat: hat))
      #expect(value[5] == bits)
      #expect(onlyByteDiffers(value, at: 5))
    }
  }

  @Test
  func triggersAreTenBitLittleEndian() {
    let full = format.buildInputReport(
      from: VirtualGamepadState(leftTrigger: 32_767, rightTrigger: 16_384)
    )

    #expect(Array(full[6...9]) == [0xFF, 0x03, 0xFF, 0x01])
  }

  @Test
  func sticksAreSignedWithBothYAxesComplemented() {
    let full = format.buildInputReport(
      from: VirtualGamepadState(
        leftStickX: 32_767,
        leftStickY: 16_384,
        rightStickX: -32_767,
        rightStickY: -16_384
      )
    )

    // X is the state value; Y is its bitwise complement (0x4000 -> 0xBFFF, -0x4000 -> 0x3FFF).
    #expect(Array(full[10...17]) == [0xFF, 0x7F, 0xFF, 0xBF, 0x01, 0x80, 0xFF, 0x3F])
  }

  @Test
  func guideTravelsInVirtualKeyPacket() {
    let pressed = format.buildAuxiliaryInputReports(
      from: VirtualGamepadState(buttons: 1 << UInt32(GamepadHIDDescriptor.ButtonBit.guide.rawValue))
    )
    let released = format.buildAuxiliaryInputReports(from: VirtualGamepadState())

    #expect(pressed == [[0x07, 0x20, 0x00, 0x02, 1, 0x5B]])
    #expect(released == [[0x07, 0x20, 0x00, 0x02, 0, 0x5B]])
    #expect(report(buttonBit: .guide) == ProtocolPacketFixtures.XboxOneGIP.neutralInputReport)
  }

  @Test
  func identityAndDescriptorDeclareGIPReports() throws {
    let profile = VirtualHIDProfileID.sdlCompatible.identity
    let parsed = try #require(
      HIDReportDescriptorParser.parse(descriptor: XboxOneGIPHIDDescriptor.descriptor)
    )

    #expect(profile.vendorID == 0x045E)
    #expect(profile.productID == 0x0B0C)
    #expect(profile.productName == "Xbox Adaptive Controller")
    #expect(format.inputReportID == 0x20)
    #expect(format.outputReportID == 0x09)
    #expect(format.outputReportPayloadSize == 12)
    // Payloads: 3 header bytes and 14 state bytes; 3 header bytes, Guide and a key code.
    #expect(parsed.payloadSizeBytesByReportID[0x20] == 17)
    #expect(parsed.payloadSizeBytesByReportID[0x07] == 5)
    #expect(format.inputReportPayloadSize == 17)
    #expect(format.buildInputReport(from: VirtualGamepadState()).count == 18)
  }

  @Test
  func descriptorFieldsSitWhereSDLReadsThem() throws {
    let parsed = try #require(
      HIDReportDescriptorParser.parse(descriptor: XboxOneGIPHIDDescriptor.descriptor)
    )
    let input = parsed.fields.filter { $0.reportID == 0x20 }
    // Bit offsets count from the first payload bit, after the report ID.
    let buttons = input.filter { $0.usagePage == 0x09 }.sorted { $0.bitOffset < $1.bitOffset }
    let firstButtonBit = 8 * 3 + 2  // after the header and two constant bits

    #expect(buttons.map(\.usage) == [8, 7, 1, 2, 3, 4, 12, 13, 14, 15, 5, 6, 9, 10])
    #expect(buttons.first?.bitOffset == firstButtonBit)
    let axes = input.filter { $0.usagePage == 0x01 }.sorted { $0.bitOffset < $1.bitOffset }
    #expect(axes.map(\.usage) == [0x32, 0x35, 0x30, 0x31, 0x33, 0x34])
    // Triggers at payload byte 5 and 7, then X, Y, Rx, Ry at bytes 9, 11, 13 and 15.
    #expect(axes.map(\.bitOffset) == [40, 56, 72, 88, 104, 120])
    #expect(
      parsed.fields.contains { $0.reportID == 0x07 && $0.usagePage == 0x09 && $0.usage == 11 }
    )
  }
}
