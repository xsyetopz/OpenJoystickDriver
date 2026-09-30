import Testing

@testable import OpenJoystickDriverKit

/// Decodes `hid-xbox-one-s-bt` reports the way SDL's HIDAPI Xbox One driver does for a 16-byte
/// Bluetooth packet (`src/joystick/hidapi/SDL_hidapi_xboxone.c`, SDL 3 line numbers; the SDL 2
/// branch has the same size dispatch and `HandleButtons16`).
private struct SDLXboxOneS16Decoder {
  var buttons: Set<String> = []
  var axes: [String: Int] = [:]
  var hat = 0

  /// `HandleStatePacket`, :1379-1383: exactly 16 bytes selects `HandleButtons16`.
  init(report data: [UInt8]) {
    precondition(data.count == 16 && data[0] == 0x01)
    let face: [(UInt8, String)] = [
      (0x01, "south"), (0x02, "east"), (0x04, "west"), (0x08, "north"), (0x10, "leftShoulder"),
      (0x20, "rightShoulder"), (0x40, "back"), (0x80, "start"),
    ]
    // `HandleButtons16`, :1256-1271: data[14] face/shoulder/back/start, data[15] bit0/1 sticks.
    for (mask, name) in face where data[14] & mask != 0 { buttons.insert(name) }
    if data[15] & 0x01 != 0 { buttons.insert("leftStick") }
    if data[15] & 0x02 != 0 { buttons.insert("rightStick") }
    // Triggers, :1425-1437: 10-bit value * 64 - 32768, clamped 32704 -> 32767.
    func trigger(_ low: UInt8, _ high: UInt8) -> Int {
      let axis = Int(UInt16(low) | UInt16(high) << 8) * 64 - 32768
      return axis == 32704 ? 32767 : axis
    }
    axes["leftTrigger"] = trigger(data[9], data[10])
    axes["rightTrigger"] = trigger(data[11], data[12])
    // Sticks, :1439-1446: u16 LE minus 0x8000.
    func stick(_ low: UInt8, _ high: UInt8) -> Int { Int(UInt16(low) | UInt16(high) << 8) - 0x8000 }
    axes["leftX"] = stick(data[1], data[2])
    axes["leftY"] = stick(data[3], data[4])
    axes["rightX"] = stick(data[5], data[6])
    axes["rightY"] = stick(data[7], data[8])
    // Hat, :1389-1420: 1..8 clockwise from up, anything else centred.
    hat = (1...8).contains(data[13]) ? Int(data[13]) : 0
  }

  /// `HandleGuidePacket`, :1450-1456: Guide is bit 0 of data[1] of report 0x02.
  static func guide(report data: [UInt8]) -> Bool { data[0] == 0x02 && data[1] & 0x01 != 0 }
}

struct XboxOneSBluetoothSDLOracleTests {
  private func decode(_ state: VirtualGamepadState) throws -> SDLXboxOneS16Decoder {
    SDLXboxOneS16Decoder(report: try XboxGeckoHIDReportFormat().buildInputReport(from: state))
  }

  @Test
  func everyButtonDecodesToItsSDLButton() throws {
    let cases: [(GamepadHIDDescriptor.ButtonBit, String)] = [
      (.a, "south"), (.b, "east"), (.x, "west"), (.y, "north"), (.leftBumper, "leftShoulder"),
      (.rightBumper, "rightShoulder"), (.back, "back"), (.start, "start"),
      (.leftStick, "leftStick"), (.rightStick, "rightStick"),
    ]
    for (bit, name) in cases {
      let decoded = try decode(VirtualGamepadState(buttons: 1 << UInt32(bit.rawValue)))
      #expect(decoded.buttons == [name])
    }
  }

  @Test
  func guideTravelsInReportTwoWhichSDLReadsAsGuide() throws {
    let pressed = VirtualGamepadState(
      buttons: 1 << UInt32(GamepadHIDDescriptor.ButtonBit.guide.rawValue)
    )
    let released = VirtualGamepadState()
    let format = try XboxGeckoHIDReportFormat()
    let pressedReports = format.buildAuxiliaryInputReports(from: pressed)
    let releasedReports = format.buildAuxiliaryInputReports(from: released)

    #expect(pressedReports.count == 1 && releasedReports.count == 1)
    #expect(SDLXboxOneS16Decoder.guide(report: pressedReports[0]))
    #expect(!SDLXboxOneS16Decoder.guide(report: releasedReports[0]))
    // Report 1 stays a 16-byte packet, so SDL takes no Guide from it.
    #expect(try decode(pressed).buttons.isEmpty)
  }

  @Test
  func sticksTriggersAndHatDecodeToSDLAxes() throws {
    let decoded = try decode(
      VirtualGamepadState(
        leftStickX: Int16.max,
        leftStickY: Int16.min + 1,
        rightStickX: 0,
        rightStickY: 16_384,
        leftTrigger: Int16.max,
        rightTrigger: 0,
        hat: .north
      )
    )
    #expect(decoded.axes["leftX"] == 0x7FFF)
    #expect(decoded.axes["leftY"] == -0x7FFF)
    #expect(decoded.axes["rightX"] == 0)
    #expect(decoded.axes["rightY"] == 0x4000)
    #expect(decoded.axes["leftTrigger"] == 32767)
    #expect(decoded.axes["rightTrigger"] == -32768)
    #expect(decoded.hat == 1)
    #expect(try decode(VirtualGamepadState()).hat == 0)
  }
}
