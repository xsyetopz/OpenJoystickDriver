import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The Guide button of a GIP pad, as the community drivers read it (issue #53, `20D6:2028`; no
/// capture of that pad exists).
///
/// - Linux `xpad.c`: `GIP_CMD_VIRTUAL_KEY` is 0x07, `GIP_OPT_ACK` 0x10 and `GIP_OPT_INTERNAL` 0x20
///   (https://raw.githubusercontent.com/torvalds/linux/master/drivers/input/joystick/xpad.c, lines
///   613, 621-622). `xpadone_process_packet` reports `BTN_MODE` from `data[4] & GENMASK(1, 0)`
///   (line 1063) and, when `data[1] == GIP_OPT_ACK | GIP_OPT_INTERNAL`, acks with `data[2]` as the
///   sequence (lines 1060-1061, 1521-1540); the ack is `GIP_CMD_ACK, GIP_OPT_INTERNAL, seq,
///   GIP_PL_LEN(9), 0x00, GIP_CMD_VIRTUAL_KEY, GIP_OPT_INTERNAL, 0x02, 0, 0, 0, 0, 0` (lines
///   1525-1534).
/// - `xone` `bus/protocol.c`: a virtual-key payload is `down` then `key`, two bytes, and the key is
///   `GIP_VKEY_LEFT_WIN` 0x5b
///   (https://raw.githubusercontent.com/medusalix/xone/master/bus/protocol.c, lines 24, 113-116,
///   1187-1208); `driver/gamepad.c` line 244-248 reports `BTN_MODE` from `down`.
/// - `xpad_device` lists `0x20d6` pads as `XTYPE_XBOXONE` with no virtual-key quirk (`xpad.c`
///   lines 346-351).
struct GIPGuideVirtualKeyTests {
  /// Header: command, options, sequence, payload length; payload: down, key.
  private static func virtualKey(down: UInt8, sequence: UInt8, options: UInt8) -> Data {
    Data([GIPCommand.virtualKey, options, sequence, 2, down, 0x5B])
  }

  @Test
  func guidePressAndReleaseReachStateAndAreAcknowledgedWithTheirSequence() throws {
    let parser = GIPDriver()
    let options = GIPOption.acknowledge | GIPOption.internal

    let press = try parser.parseReport(Self.virtualKey(down: 1, sequence: 0x07, options: options))
    #expect(press.contains(.press(.guide)))
    #expect(
      parser.drainPendingWrites().usbBytes == [
        [GIPCommand.acknowledge, 0x20, 0x07, 9, 0, GIPCommand.virtualKey, 0x20, 2, 0, 0, 0, 0, 0]
      ]
    )

    let release = try parser.parseReport(Self.virtualKey(down: 0, sequence: 0x08, options: options))
    #expect(release.contains(.release(.guide)))
    #expect(
      parser.drainPendingWrites().usbBytes == [
        [GIPCommand.acknowledge, 0x20, 0x08, 9, 0, GIPCommand.virtualKey, 0x20, 2, 0, 0, 0, 0, 0]
      ]
    )
  }

  /// `xpad.c` reads only `data[4]`, the first payload byte, and never the key (line 1063).
  @Test(arguments: [[UInt8(1)], [1, 0x00], [1, 0x5C]])
  func guideReadsFirstPayloadByteWhateverKey(payload: [UInt8]) throws {
    let parser = GIPDriver()
    let header: [UInt8] = [GIPCommand.virtualKey, GIPOption.internal, 0x07, UInt8(payload.count)]
    #expect(try parser.parseReport(Data(header + payload)).contains(.press(.guide)))
  }
}
