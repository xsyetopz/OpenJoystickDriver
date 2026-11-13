import Testing

@testable import OpenJoystickDriverKit

/// Parses `SDLCompatible` reports the way SDL's HIDAPI Xbox One driver does for a device it does
/// not read as Bluetooth (`src/joystick/hidapi/SDL_hidapi_xboxone.c`, SDL 3.4.16): every report is
/// a GIP packet whose first byte, the report ID, is the command.
private struct SDLGIPParser {
  var buttons: Set<String> = []
  var axes: [String: Int] = [:]
  var hat = 0
  var guide: Bool?
  var ignored = false

  /// `HIDAPI_GIP_ProcessData` (:1913-1933), `HIDAPI_GIP_DecodeHeader` (:1663-1679) with its
  /// variable-length integer, `HIDAPI_GIP_ProcessPacket` (:1889-1911) and
  /// `HIDAPI_GIP_DispatchPacket` (:1737-1841).
  init(report data: [UInt8]) {
    precondition(data.count > 3)
    let command = data[0]
    let options = data[1]
    // Length: one byte below 0x80, which every packet here uses.
    precondition(data[3] & 0x80 == 0)
    let length = Int(data[3])
    let payload = Array(data[4...])
    // The packet must not be shortened: SDL rescales a report that is.
    precondition(payload.count == length)
    // Chunk and acknowledge options would divert the packet.
    precondition(options & 0xD0 == 0)
    // A packet "for a device plugged into the controller" is skipped.
    guard options & 0x0F == 0 else {
      ignored = true
      return
    }
    if options & 0x20 != 0 {
      // GIP_CMD_VIRTUAL_KEY, `HandleModePacket` (:1242-1247).
      guard command == 0x07 else {
        ignored = true
        return
      }
      guide = payload[0] & 0x01 != 0
      return
    }
    // GIP_CMD_INPUT (:1812), `HandleStatePacket` (:1036-1233).
    guard command == 0x20 else {
      ignored = true
      return
    }
    // Start/back/face buttons, :1051-1058.
    let face: [(UInt8, String)] = [
      (0x04, "start"), (0x08, "back"), (0x10, "south"), (0x20, "east"), (0x40, "west"),
      (0x80, "north"),
    ]
    for (mask, name) in face where payload[0] & mask != 0 { buttons.insert(name) }
    // D-pad as a hat, shoulders and sticks, :1060-1087.
    if payload[1] & 0x01 != 0 { hat |= 1 }
    if payload[1] & 0x02 != 0 { hat |= 4 }
    if payload[1] & 0x04 != 0 { hat |= 8 }
    if payload[1] & 0x08 != 0 { hat |= 2 }
    let shoulders: [(UInt8, String)] = [
      (0x10, "leftShoulder"), (0x20, "rightShoulder"), (0x40, "leftStick"), (0x80, "rightStick"),
    ]
    for (mask, name) in shoulders where payload[1] & mask != 0 { buttons.insert(name) }
    // Triggers, :1202-1218: 10-bit value * 64 - 32768, 32704 clamped to 32767.
    func trigger(_ low: UInt8, _ high: UInt8) -> Int {
      let axis = Int(Int16(bitPattern: UInt16(low) | UInt16(high) << 8)) * 64 - 32768
      return axis == 32704 ? 32767 : axis
    }
    axes["leftTrigger"] = trigger(payload[2], payload[3])
    axes["rightTrigger"] = trigger(payload[4], payload[5])
    // Sticks, :1220-1227: signed 16-bit, Y axes complemented.
    func stick(_ low: UInt8, _ high: UInt8) -> Int {
      Int(Int16(bitPattern: UInt16(low) | UInt16(high) << 8))
    }
    axes["leftX"] = stick(payload[6], payload[7])
    axes["leftY"] = Int(~Int16(stick(payload[8], payload[9])))
    axes["rightX"] = stick(payload[10], payload[11])
    axes["rightY"] = Int(~Int16(stick(payload[12], payload[13])))
  }
}

struct XboxOneGIPSDLOracleTests {
  private let format = XboxOneGIPHIDReportFormat()

  private func parse(_ state: VirtualGamepadState) -> SDLGIPParser {
    SDLGIPParser(report: format.buildInputReport(from: state))
  }

  @Test
  func everyButtonParsesToItsSDLButton() {
    let cases: [(GamepadHIDDescriptor.ButtonBit, String)] = [
      (.a, "south"), (.b, "east"), (.x, "west"), (.y, "north"), (.leftBumper, "leftShoulder"),
      (.rightBumper, "rightShoulder"), (.back, "back"), (.start, "start"),
      (.leftStick, "leftStick"), (.rightStick, "rightStick"),
    ]
    for (bit, name) in cases {
      let parsed = parse(VirtualGamepadState(buttons: 1 << UInt32(bit.rawValue)))
      #expect(parsed.buttons == [name])
      #expect(!parsed.ignored)
    }
  }

  @Test
  func guideTravelsInVirtualKeyPacketSDLReadsAsGuide() {
    let pressed = format.buildAuxiliaryInputReports(
      from: VirtualGamepadState(buttons: 1 << UInt32(GamepadHIDDescriptor.ButtonBit.guide.rawValue))
    )
    let released = format.buildAuxiliaryInputReports(from: VirtualGamepadState())

    #expect(pressed.count == 1 && released.count == 1)
    #expect(SDLGIPParser(report: pressed[0]).guide == true)
    #expect(SDLGIPParser(report: released[0]).guide == false)
  }

  @Test
  func sticksTriggersAndDpadParseToSDLAxes() {
    let parsed = parse(
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

    #expect(parsed.axes["leftX"] == 0x7FFF)
    #expect(parsed.axes["leftY"] == -0x7FFF)
    #expect(parsed.axes["rightX"] == 0)
    #expect(parsed.axes["rightY"] == 0x4000)
    #expect(parsed.axes["leftTrigger"] == 32_767)
    #expect(parsed.axes["rightTrigger"] == -32_768)
    #expect(parsed.hat == 1)
    #expect(parse(VirtualGamepadState()).hat == 0)
    #expect(parse(VirtualGamepadState()).axes["leftY"] == 0)
  }

  @Test
  func diagonalHatsCombineSDLHatBits() {
    #expect(parse(VirtualGamepadState(hat: .northEast)).hat == 1 | 2)
    #expect(parse(VirtualGamepadState(hat: .southWest)).hat == 4 | 8)
  }
}
