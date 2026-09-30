import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Reports in the SDL `SteamDeckStatePacket_t` layout after the 4-byte `ValveInReportHeader_t`.
/// The layout comes from SDL `steam/controller_structs.h`; it is not a hardware capture.
private enum DeckReport {
  static func state(
    packet: UInt32 = 1,
    low: UInt32 = 0,
    high: UInt32 = 0,
    words: [Int: Int16] = [:]
  ) -> Data {
    var bytes = [UInt8](repeating: 0, count: 64)
    bytes.replaceSubrange(0..<4, with: [0x01, 0x00, 0x09, 64])
    put32(&bytes, 4, packet)
    put32(&bytes, 8, low)
    put32(&bytes, 12, high)
    for (offset, value) in words { put16(&bytes, offset, UInt16(bitPattern: value)) }
    return Data(bytes)
  }

  static func put32(_ bytes: inout [UInt8], _ offset: Int, _ value: UInt32) {
    put16(&bytes, offset, UInt16(truncatingIfNeeded: value))
    put16(&bytes, offset + 2, UInt16(truncatingIfNeeded: value >> 16))
  }

  static func put16(_ bytes: inout [UInt8], _ offset: Int, _ value: UInt16) {
    bytes[offset] = UInt8(truncatingIfNeeded: value)
    bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
  }
}

@Suite
struct SteamDeckDriverTests {

  @Test
  func mapsButtonBitsAsSDLReportsThem() throws {
    let low: [(UInt32, ControlID)] = [
      (0x0000_0001, .rightTriggerButton), (0x0000_0002, .leftTriggerButton),
      (0x0000_0004, .rightShoulder), (0x0000_0008, .leftShoulder), (0x0000_0010, .faceNorth),
      (0x0000_0020, .faceEast), (0x0000_0040, .faceWest), (0x0000_0080, .faceSouth),
      (0x0000_1000, .view), (0x0000_2000, .guide), (0x0000_4000, .menu),
      (0x0000_8000, .paddleLeft2), (0x0001_0000, .paddleRight2), (0x0002_0000, .leftTrackpadClick),
      (0x0004_0000, .rightTrackpadClick), (0x0040_0000, .leftStickClick),
      (0x0400_0000, .rightStickClick),
    ]
    let high: [(UInt32, ControlID)] = [
      (0x0000_0200, .paddleLeft1), (0x0000_0400, .paddleRight1), (0x0000_4000, .leftStickTouch),
      (0x0000_8000, .rightStickTouch), (0x0004_0000, .auxiliary1),
    ]
    for (mask, control) in low {
      let driver = SteamDeckDriver()
      #expect(try driver.parseReport(DeckReport.state(low: mask)).contains(.press(control)))
      #expect(try driver.parseReport(DeckReport.state(packet: 2)).contains(.release(control)))
    }
    for (mask, control) in high {
      let driver = SteamDeckDriver()
      #expect(try driver.parseReport(DeckReport.state(high: mask)).contains(.press(control)))
    }
  }

  @Test
  func decodesTheDPadBitsIntoTheHat() throws {
    let cases: [(UInt32, HatDirection)] = [
      (0x0100, .north), (0x0300, .northEast), (0x0200, .east), (0x0A00, .southEast),
      (0x0800, .south), (0x0C00, .southWest), (0x0400, .west), (0x0500, .northWest),
      (0x0900, .neutral),
    ]
    for (buttons, direction) in cases {
      let event = try SteamDeckDriver().parseReport(DeckReport.state(low: buttons))
      #expect(event?.state.hat == direction)
    }
  }

  @Test
  func decodesUnsignedTriggersAndSticksWithYDown() throws {
    let words: [Int: Int16] = [44: 32767, 46: 0, 48: 32767, 50: 32767, 52: -32767, 54: -32767]
    let event = try #require(try SteamDeckDriver().parseReport(DeckReport.state(words: words)))
    #expect(event.state.leftTrigger == .max)
    #expect(event.state.rightTrigger == .min)
    #expect(event.state.leftStick == StickPosition(x: 1, yDown: -1))
    #expect(event.state.rightStick == StickPosition(x: -1, yDown: 1))
  }

  @Test
  func rejectsReportsOutsideTheDeckStateHeader() throws {
    var wrongType = Array(DeckReport.state(low: 0x80))
    wrongType[2] = 0x01
    #expect(try SteamDeckDriver().parseReport(Data(wrongType)) == nil)
    #expect(try SteamDeckDriver().parseReport(DeckReport.state(low: 0x80).prefix(63)) == nil)
  }

  /// Accel sits at 24 and gyro at 30, and SDL maps both as (x, z, -y), so no axis is reflected.
  @Test
  func motionReadsTheDeckOffsetsWithoutReflectingGyroY() throws {
    let driver = SteamDeckDriver()
    let words: [Int: Int16] = [26: 16384, 30: 16384, 32: 16384]
    let sample = try #require(try driver.parseReport(DeckReport.state(words: words))?.motion.first)
    #expect(abs(sample.acceleration.y - 9.80665) < 0.001)
    #expect(sample.acceleration.x == 0 && sample.acceleration.z == 0)
    #expect(abs(sample.angularVelocity.x - 1000 * Double.pi / 180) < 0.001)
    #expect(abs(sample.angularVelocity.y - 1000 * Double.pi / 180) < 0.001)
    #expect(sample.angularVelocity.z == 0)
    #expect(try driver.parseReport(DeckReport.state(words: words))?.motion.isEmpty == true)
  }

  @Test
  func touchedTrackpadCarriesItsPressure() throws {
    let report = DeckReport.state(low: 0x0008_0000, words: [16: 32767, 56: 16384, 58: 9])
    let event = try #require(try SteamDeckDriver().parseReport(report))
    let left = try #require(event.touchFrames.first { $0.surface == .left }?.contacts.first)
    let right = try #require(event.touchFrames.first { $0.surface == .right }?.contacts.first)
    #expect(left.isActive && left.pressure == UnipolarValue(normalized: 0.5))
    #expect(!right.isActive && right.pressure == nil)
    #expect(event.state.pressed.contains(.leftTrackpadTouch))
  }

  @Test
  func lizardModeSettingsWatchdogAndRumbleBytes() throws {
    let driver = SteamDeckDriver()
    let startup = driver.activationWrites().hidFeatures
    #expect(startup.map(\.reportID) == [0, 0])
    #expect(startup.map(\.bytes.count) == [64, 64])
    #expect(startup[0].bytes.first == 0x81)
    #expect(
      Array(startup[1].bytes.prefix(20)) == [
        0x87, 18, 24, 0, 0, 7, 7, 0, 8, 7, 0, 52, 0xFF, 0xFF, 53, 0xFF, 0xFF, 71, 0, 0,
      ]
    )

    #expect(driver.sessionPlan.hidKeepAliveIntervalNanoseconds == 1_000_000_000)
    let feed = driver.keepAliveWrites().hidFeatures.map { Array($0.bytes.prefix(5)) }
    #expect(feed == [[0x81, 0, 0, 0, 0], [0x87, 3, 8, 7, 0]])

    let shutdown = driver.deactivationWrites().hidFeatures.map { $0.bytes.first }
    #expect(shutdown == [0x85, 0x8E])

    let intensities = RumbleIntensities(
      leftMain: UnipolarValue(0x1234),
      rightMain: UnipolarValue(0xABCD)
    )
    let rumble = driver.encoded(.setRumble(intensities, duration: .milliseconds(500))).onlyReport
    #expect(rumble.reportID == 0)
    #expect(Array(rumble.bytes.prefix(12)) == [0xEB, 0, 0, 0, 0, 0x34, 0x12, 0xCD, 0xAB, 2, 0, 0])
    let stop = driver.encoded(.stopRumble).onlyReport
    #expect(Array(stop.bytes.prefix(10)) == [0xEB, 0, 0, 0, 0, 0, 0, 0, 0, 2])
    #expect(driver.encoded(.setPlayerIndicator(.player1)) == nil)
  }
}
