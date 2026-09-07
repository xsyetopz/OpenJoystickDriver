import Foundation
import Testing

@testable import OpenJoystickDriverKit

private func makeXIDReport(
  digital: UInt8 = 0,
  analogA: UInt8 = 0,
  analogB: UInt8 = 0,
  analogX: UInt8 = 0,
  analogY: UInt8 = 0,
  black: UInt8 = 0,
  white: UInt8 = 0,
  lt: UInt8 = 0,
  rt: UInt8 = 0,
  lsx: Int16 = 0,
  lsy: Int16 = 0
) -> Data {
  var r = [UInt8](repeating: 0, count: 20)
  r[0] = 0x00
  r[1] = 0x14
  r[2] = digital
  r[4] = analogA
  r[5] = analogB
  r[6] = analogX
  r[7] = analogY
  r[8] = black
  r[9] = white
  r[10] = lt
  r[11] = rt
  let lsxBits = UInt16(bitPattern: lsx)
  r[12] = UInt8(lsxBits & 0xFF)
  r[13] = UInt8(lsxBits >> 8)
  let lsyBits = UInt16(bitPattern: lsy)
  r[14] = UInt8(lsyBits & 0xFF)
  r[15] = UInt8(lsyBits >> 8)
  return Data(r)
}

struct XIDParserTests {
  @Test func shortReportIsIgnored() throws {
    #expect(try XIDParser().parse(data: Data([0x00, 0x14, 0x00])).isEmpty)
  }

  @Test func analogABecomesDigitalPress() throws {
    let parser = XIDParser()
    _ = try parser.parse(data: makeXIDReport())
    let events = try parser.parse(data: makeXIDReport(analogA: 0xFF))
    #expect(events.contains(.buttonPressed(.a)))
  }

  @Test func digitalStartAndDpadMatchLinuxXpad() throws {
    let parser = XIDParser()
    _ = try parser.parse(data: makeXIDReport())
    let events = try parser.parse(data: makeXIDReport(digital: 0x11))
    #expect(events.contains(.buttonPressed(.start)))
    #expect(events.contains(.dpadChanged(.north)))
  }

  @Test func analogTriggersAndBlackWhiteShoulders() throws {
    let parser = XIDParser()
    _ = try parser.parse(data: makeXIDReport())
    let events = try parser.parse(data: makeXIDReport(black: 0x80, white: 0x40, lt: 128, rt: 255))
    #expect(events.contains(.buttonPressed(.leftBumper)))
    #expect(events.contains(.buttonPressed(.rightBumper)))
    #expect(events.contains(.leftTriggerChanged(128.0 / 255.0)))
    #expect(events.contains(.rightTriggerChanged(1)))
  }

  @Test func analogZeroReleasesFaceButton() throws {
    let parser = XIDParser()
    _ = try parser.parse(data: makeXIDReport(analogY: 0x20))
    let events = try parser.parse(data: makeXIDReport(analogY: 0))
    #expect(events.contains(.buttonReleased(.y)))
  }
}
