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
  func neutralReportIsGIPInputPacket() {
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

    #expect(pressed.first == [0x07, 0x20, 0x00, 0x02, 1, 0x5B])
    #expect(released.first == [0x07, 0x20, 0x00, 0x02, 0, 0x5B])
    #expect(pressed.last == [0x02, 1])
    #expect(report(buttonBit: .guide) == ProtocolPacketFixtures.XboxOneGIP.neutralInputReport)
  }

  @Test
  func identityAndDescriptorDeclareGIPReports() throws {
    let profile = VirtualHIDProfileID.sdlCompatible.identity
    let parsed = try #require(
      HIDReportDescriptorParser.parse(descriptor: XboxOneGIPHIDDescriptor.descriptor)
    )

    #expect(profile.vendorID == 0x045E)
    #expect(profile.productID == 0x0B13)
    #expect(profile.productName == "Xbox Wireless Controller")
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
  func descriptorDeclaresGIPReportsAsVendorData() throws {
    let parsed = try #require(
      HIDReportDescriptorParser.parse(descriptor: XboxOneGIPHIDDescriptor.descriptor)
    )

    let gipFields = parsed.fields.filter { [0x20, 0x07].contains($0.reportID) }

    #expect(!gipFields.isEmpty)
    #expect(gipFields.allSatisfy { $0.usagePage == 0xFF00 })
  }

  @Test
  func bluetoothReportCarriesStateSDL2Reads() {
    let state = VirtualGamepadState(
      buttons: 1 << UInt32(GamepadHIDDescriptor.ButtonBit.a.rawValue),
      leftStickX: 0x1234,
      leftStickY: -0x1234,
      rightStickX: 0x4321,
      leftTrigger: Int16.max,
      hat: .north
    )
    let bluetooth = XboxSeriesBluetoothHIDReportFormat().buildInputReport(from: state)

    let mirrored = format.buildAuxiliaryInputReports(from: state)[1]

    #expect(mirrored.count == 17)
    #expect(mirrored[0] == 0x01)
    // Only the masked bits of the two left stick low bytes differ from the Bluetooth report.
    let unmasked = mirrored.indices.filter { ![1, 3].contains($0) }
    #expect(unmasked.allSatisfy { mirrored[$0] == bluetooth[$0] })
    #expect(mirrored[1] == bluetooth[1] & 0x78)
    #expect(mirrored[3] & 0x70 == bluetooth[3] & 0x70)
  }

  /// SDL 3's `GIP_ReceivePacket` drops a packet that is not a chunk and whose length, starting at
  /// byte 3, runs past the report's end, before it reads the command or the attachment.
  @Test
  func sdl3DropsBluetoothReportAtEveryLeftStickPosition() {
    for x in stride(from: Int(Int16.min), through: Int(Int16.max), by: 251) {
      for y in [Int16.min, -1, 0, 1, 0x7F, 0x80, Int16.max] {
        let report = format.bluetoothStateReport(
          from: VirtualGamepadState(leftStickX: Int16(x), leftStickY: y)
        )
        #expect(report[1] & 0x87 == 0)
        #expect(report[3] & 0x80 == 0)
        #expect(3 + 1 + Int(report[3]) > report.count)
      }
    }
  }

  /// GameController and SDL 2 read the Bluetooth reports' usages, so they match the Xbox Series
  /// Bluetooth descriptor's field for field.
  @Test
  func descriptorDeclaresBluetoothReportsWithTheirUsages() throws {
    let parsed = try #require(
      HIDReportDescriptorParser.parse(descriptor: XboxOneGIPHIDDescriptor.descriptor)
    )
    let bluetooth = try #require(
      HIDReportDescriptorParser.parse(descriptor: XboxSeriesBluetoothHIDDescriptor.descriptor)
    )

    func layout(_ descriptor: HIDParsedDescriptor) -> [String] {
      descriptor.fields.filter { [0x01, 0x02, 0x04].contains($0.reportID) }.map {
        "\($0.reportID) \($0.bitOffset) \($0.bitSize) \($0.usagePage) \($0.usage) "
          + "\($0.logicalMin) \($0.logicalMax)"
      }
    }

    #expect(!layout(parsed).isEmpty)
    #expect(layout(parsed) == layout(bluetooth))
    #expect(parsed.payloadSizeBytesByReportID[0x01] == 16)
    #expect(parsed.payloadSizeBytesByReportID[0x02] == 1)
    #expect(format.outputReportIDs == [0x09, 0x03])
  }

  @Test
  func sdl2BluetoothRumbleReportDecodes() throws {
    let command = try consumerOutput(0x03, [0x03, 0x03, 0, 0, 40, 60, 25, 0, 0], in: format)

    #expect(command == .consumerRumble(left: 40, right: 60, durationMs: 250))
  }
}
