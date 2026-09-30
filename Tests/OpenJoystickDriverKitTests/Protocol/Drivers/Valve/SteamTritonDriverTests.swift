import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Reports in the SDL `TritonMTUNoQuat_t` (`0x42`, `0x45`) and `TritonMTUNoQuat32TS_t` (`0x47`)
/// layouts, with the report ID at byte 0. The layouts come from SDL `controller_structs.h` at
/// `release-3.4.16`; they are not a hardware capture.
private enum TritonReport {
  static func state(
    id: UInt8 = 0x42,
    buttons: UInt32 = 0,
    words: [Int: Int16] = [:],
    imuCounter: UInt32 = 0
  ) -> Data {
    var bytes = [UInt8](repeating: 0, count: 64)
    bytes[0] = id
    for index in 0..<4 { bytes[2 + index] = UInt8(truncatingIfNeeded: buttons >> (8 * index)) }
    for (offset, value) in words { put(&bytes, offset, UInt16(bitPattern: value)) }
    if id == 0x47 {
      put(&bytes, 32, UInt16(truncatingIfNeeded: imuCounter))
    } else {
      put(&bytes, 30, UInt16(truncatingIfNeeded: imuCounter))
      put(&bytes, 32, UInt16(truncatingIfNeeded: imuCounter >> 16))
    }
    return Data(bytes)
  }

  static func put(_ bytes: inout [UInt8], _ offset: Int, _ value: UInt16) {
    bytes[offset] = UInt8(truncatingIfNeeded: value)
    bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
  }
}

@Suite
struct SteamTritonDriverTests {

  @Test
  func tritonRowsSelectTheTritonDriverAndStoreTheirTransportVariant() throws {
    let registry = ProtocolDriverRegistry()
    let rows: [(UInt16, PhysicalProtocolVariantID)] = [
      (0x1302, .wired), (0x1303, .bluetoothLE), (0x1304, .dongle), (0x1305, .dongle),
    ]
    for (productID, variant) in rows {
      let record = try #require(
        registry.record(for: DeviceIdentifier(vendorID: 0x28DE, productID: productID))
      )
      #expect(record.quirks == [.triton])
      #expect(record.physicalProtocolVariant == variant)
    }
  }

  @Test
  func mapsButtonBitsAsSDLReportsThem() throws {
    let controls: [(UInt32, ControlID)] = [
      (0x0000_0001, .faceSouth), (0x0000_0002, .faceEast), (0x0000_0004, .faceWest),
      (0x0000_0008, .faceNorth), (0x0000_0010, .auxiliary1), (0x0000_0020, .rightStickClick),
      (0x0000_0040, .menu), (0x0000_0080, .paddleRight1), (0x0000_0100, .paddleRight2),
      (0x0000_0200, .rightShoulder), (0x0000_4000, .view), (0x0000_8000, .leftStickClick),
      (0x0001_0000, .guide), (0x0002_0000, .paddleLeft1), (0x0004_0000, .paddleLeft2),
      (0x0008_0000, .leftShoulder), (0x0010_0000, .rightStickTouch),
      (0x0040_0000, .rightTrackpadClick), (0x0080_0000, .rightTriggerButton),
      (0x0100_0000, .leftStickTouch), (0x0400_0000, .leftTrackpadClick),
      (0x0800_0000, .leftTriggerButton),
    ]
    for (mask, control) in controls {
      let driver = SteamTritonDriver()
      #expect(try driver.parseReport(TritonReport.state(buttons: mask)).contains(.press(control)))
      #expect(try driver.parseReport(TritonReport.state()).contains(.release(control)))
    }
  }

  @Test
  func decodesTheDPadBitsIntoTheHat() throws {
    let cases: [(UInt32, HatDirection)] = [
      (0x2000, .north), (0x2800, .northEast), (0x0800, .east), (0x0C00, .southEast),
      (0x0400, .south), (0x1400, .southWest), (0x1000, .west), (0x3000, .northWest),
      (0x2400, .neutral),
    ]
    for (buttons, direction) in cases {
      let event = try SteamTritonDriver().parseReport(TritonReport.state(buttons: buttons))
      #expect(event?.state.hat == direction)
    }
  }

  @Test
  func decodesSticksWithYDownAndClampsNegativeTriggers() throws {
    let report = TritonReport.state(words: [
      6: 32767, 8: -100, 10: -32768, 12: 32767, 14: 32767, 16: -32767,
    ])
    let event = try #require(try SteamTritonDriver().parseReport(report))
    #expect(event.state.leftTrigger == .max)
    #expect(event.state.rightTrigger == .min)
    #expect(event.state.leftStick == StickPosition(x: -1, yDown: -1))
    #expect(event.state.rightStick == StickPosition(x: 1, yDown: 1))
  }

  @Test
  func timestampedLayoutMovesTheTrackpadsAndKeepsTheSticks() throws {
    let words: [Int: Int16] = [10: 32767, 20: 32767, 24: 16384, 26: -32768]
    let report = TritonReport.state(id: 0x47, buttons: 0x0220_0000, words: words)
    let event = try #require(try SteamTritonDriver().parseReport(report))
    #expect(event.state.leftStick == StickPosition(x: 1, yDown: 0))
    let left = try #require(event.touchFrames.first { $0.surface == .left }?.contacts.first)
    let right = try #require(event.touchFrames.first { $0.surface == .right }?.contacts.first)
    #expect(left.isActive && right.isActive)
    #expect(left.x > right.x)
    #expect(left.pressure == UnipolarValue(normalized: 0.5))
  }

  @Test
  func inactiveTrackpadsCarryNoPressure() throws {
    let event = try #require(
      try SteamTritonDriver().parseReport(TritonReport.state(words: [22: 9]))
    )
    #expect(event.touchFrames.flatMap(\.contacts).allSatisfy { !$0.isActive && $0.pressure == nil })
  }

  @Test
  func motionKeepsTheRawAxesAndSkipsARepeatedTimestamp() throws {
    let driver = SteamTritonDriver()
    let report = TritonReport.state(words: [36: 16384, 40: 16384], imuCounter: 1000)
    let sample = try #require(try driver.parseReport(report)?.motion.first)
    #expect(abs(sample.acceleration.y - 9.80665) < 0.001)
    #expect(sample.acceleration.x == 0 && sample.acceleration.z == 0)
    #expect(abs(sample.angularVelocity.x - 1000 * Double.pi / 180) < 0.001)
    #expect(sample.angularVelocity.y == 0 && sample.angularVelocity.z == 0)
    #expect(try driver.parseReport(report)?.motion.isEmpty == true)
    let next = TritonReport.state(imuCounter: 5000)
    let later = try #require(try driver.parseReport(next, at: 1_000_000)?.motion.first)
    #expect(later.timestamp.sequenceIndex == sample.timestamp.sequenceIndex + 1)
  }

  @Test
  func dongleWaitsForItsControllerAndDropsItOnDisconnect() throws {
    let driver = SteamTritonDriver(isDongle: true)
    #expect(driver.sessionPlan.requiresInputConnectionBeforeOutput)
    #expect(driver.keepAliveWrites().isEmpty)
    #expect(try driver.parseReport(Data([0x79, 0x02])) == nil)
    #expect(driver.consumeInputConnectionStateChange() == .connected)
    #expect(driver.inputConnectionWrites(for: .connected).hidFeatures.count == 2)

    _ = try driver.parseReport(Data([0x43, 0x02, 55]))
    #expect(driver.power?.charging == .charging)
    #expect(driver.power?.battery == BatteryLevel(percentage: 55...55))

    #expect(try driver.parseReport(Data([0x79, 0x01])) == nil)
    #expect(driver.consumeInputConnectionStateChange() == .disconnected)
    #expect(driver.power == nil)
    #expect(driver.keepAliveWrites().isEmpty)

    // A state report is itself proof of a connected controller.
    _ = try driver.parseReport(TritonReport.state(buttons: 1))
    #expect(driver.consumeInputConnectionStateChange() == .connected)
  }

  @Test
  func settingsTravelAsSixtyFourByteFeatureReports() {
    let startup = SteamTritonDriver().activationWrites().hidFeatures
    #expect(startup.map(\.reportID) == [1, 1])
    #expect(startup.map(\.bytes.count) == [64, 64])
    #expect(Array(startup[0].bytes.prefix(6)) == [0x01, 0x87, 0x03, 9, 0, 0])
    #expect(Array(startup[1].bytes.prefix(6)) == [0x01, 0x87, 0x03, 48, 0x18, 0])
    let shutdown = SteamTritonDriver().deactivationWrites().hidFeatures
    #expect(Array(shutdown.map { Array($0.bytes.prefix(6)) }) == [[0x01, 0x87, 0x03, 48, 0, 0]])
  }

  @Test
  func rumbleRepeatsEveryTickUntilStoppedAndLizardModeOffEveryThreeSeconds() throws {
    let driver = SteamTritonDriver()
    #expect(driver.sessionPlan.hidKeepAliveIntervalNanoseconds == 40_000_000)
    let intensities = RumbleIntensities(
      leftMain: UnipolarValue(0x1234),
      rightMain: UnipolarValue(0xABCD)
    )
    let report = driver.encoded(.setRumble(intensities, duration: .milliseconds(500))).onlyReport
    #expect(report.reportID == 0x80)
    #expect(report.bytes == [0x80, 0, 0, 0, 0x34, 0x12, 0, 0xCD, 0xAB, 0])

    let ticks = (0..<76).map { _ in driver.keepAliveWrites() }
    #expect(ticks.allSatisfy { $0.hidOutputs == [report] })
    #expect(ticks.enumerated().filter { !$0.element.hidFeatures.isEmpty }.map(\.offset) == [0, 75])

    let stop = driver.encoded(.stopRumble).onlyReport
    #expect(stop.bytes == [0x80] + [UInt8](repeating: 0, count: 9))
    #expect(driver.keepAliveWrites().hidOutputs.isEmpty)
    #expect(driver.encoded(.setPlayerIndicator(.player1)) == nil)
  }
}
