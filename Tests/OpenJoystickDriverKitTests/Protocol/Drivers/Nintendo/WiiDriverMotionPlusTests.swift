import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct WiiDriverMotionPlusTests {
  private typealias Slow = (yaw: Bool, roll: Bool, pitch: Bool)

  private let driver = WiiDriver(tuning: nil, irFormat: nil)

  /// A mode `0x35` report: the core bytes, a still accelerometer, then the six extension bytes.
  private func report(_ frame: [UInt8]) throws -> ControllerEvent? {
    try driver.parseReport(
      Data([0x35, 0, 0, 0x80, 0x80, 0x80] + frame + [UInt8](repeating: 0, count: 10))
    )
  }

  /// A gyro frame of the given 14-bit readings; a set flag means the slow scale.
  private func gyroFrame(yaw: Int, slow: Slow = (true, true, true)) -> [UInt8] {
    let roll = 8192
    let pitch = 8192
    let high = { (value: Int) in UInt8(value >> 8) << 2 }
    return [
      UInt8(yaw & 0xFF), UInt8(roll & 0xFF), UInt8(pitch & 0xFF),
      high(yaw) | (slow.yaw ? 2 : 0) | (slow.pitch ? 1 : 0),
      high(roll) | (slow.roll ? 2 : 0) | 1,
      high(pitch) | 0x02,
    ]
  }

  @Test
  func theFastFlagScalesTheAxisByTheFastOverSlowRatio() throws {
    driver.accelerometerCalibration = WiiDriver.AccelerometerCalibration([
      0x80, 0x80, 0x80, 0, 0xC0, 0xC0, 0xC0, 0, 0, 0,
    ])
    driver.extensionKind = .known("MotionPlus")
    _ = try report(gyroFrame(yaw: 9192))
    let slowRate = WiiDriver.degreesPerSecond(try #require(driver.gyro))[1]
    _ = try report(gyroFrame(yaw: 9192, slow: (false, true, true)))
    let fast = try #require(driver.gyro)
    #expect(fast.yawFast && !fast.rollFast && !fast.pitchFast)
    #expect(abs(WiiDriver.degreesPerSecond(fast)[1] - slowRate * 2000 / 440) < 1e-9)
    let sample = try #require(try report(gyroFrame(yaw: 9192))?.motion.first)
    #expect(abs(sample.angularVelocity.y - slowRate * .pi / 180) < 1e-9)
    #expect(sample.angularVelocity.x == 0)
  }

  @Test
  func theRestOffsetIsTheMeanOfAStillWindowAndIsSubtracted() throws {
    driver.accelerometerCalibration = WiiDriver.AccelerometerCalibration([
      0x80, 0x80, 0x80, 0, 0xC0, 0xC0, 0xC0, 0, 0, 0,
    ])
    driver.extensionKind = .known("MotionPlus")
    // The first frame has no earlier accelerometer reading, so it does not count.
    for _ in 0..<WiiDriver.gyroRestWindow { _ = try report(gyroFrame(yaw: 8200)) }
    #expect(!driver.isGyroRestReady)
    _ = try report(gyroFrame(yaw: 8200))
    #expect(driver.isGyroRestReady)
    let sample = try #require(try report(gyroFrame(yaw: 8200))?.motion.first)
    #expect(abs(sample.angularVelocity.y) < 1e-9)
  }

  @Test
  func aFastFrameRestartsTheRestWindow() throws {
    driver.extensionKind = .known("MotionPlus")
    for _ in 0..<WiiDriver.gyroRestWindow { _ = try report(gyroFrame(yaw: 8192)) }
    _ = try report(gyroFrame(yaw: 8192, slow: (false, true, true)))
    _ = try report(gyroFrame(yaw: 8192))
    #expect(!driver.isGyroRestReady)
  }

  @Test
  func nunchukPassthroughFramesEachChangeOnlyTheirOwnControls() throws {
    driver.extensionKind = .known("MotionPlusNunchuk")
    // Stick at rest, C and Z released (bits 3 and 2 set), and bit 1 clear: an extension frame.
    #expect(try report([0x80, 0x80, 0x80, 0x80, 0x80, 0x0C])?.state.leftStick == .center)
    let gyroEvent = try #require(try report(gyroFrame(yaw: 9000)))
    #expect(gyroEvent.state == .neutral)
    let before = try #require(driver.gyro)
    // Z down and the stick right: the gyro holds.
    let pressed = try #require(try report([0xFF, 0x80, 0x80, 0x80, 0x80, 0x08]))
    #expect(pressed.state.pressed == [.leftTrigger])
    #expect(pressed.state.leftStick.x.rawValue >= 32_000)
    #expect(driver.gyro == before)
    // The next gyro frame leaves the buttons and the stick as they were.
    let held = try #require(try report(gyroFrame(yaw: 9100)))
    #expect(held.state == pressed.state)
    #expect(driver.gyro != before)
  }

  @Test
  func classicPassthroughKeepsTheDPadAndTheButtonsOfItsFrame() throws {
    driver.extensionKind = .known("MotionPlusClassic")
    _ = try report([0x21, 0x21, 0x10, 0x10, 0xFF, 0xFC])
    // The a button (byte 5 bit 4) and d-pad up (byte 0 bit 0) down.
    let down = try #require(try report([0x20, 0x21, 0x10, 0x10, 0xFF, 0xEC]))
    #expect(down.state.pressed == [.east, .dpadUp])
    _ = try report(gyroFrame(yaw: 8192))
    #expect(driver.gyro != nil)
  }

  /// Feeds `report` and returns the memory writes and reads it queued, as their first bytes.
  private func feed(_ report: [UInt8]) throws -> [[UInt8]] {
    _ = try driver.parseReport(Data(report))
    return driver.drainPendingWrites().compactMap {
      if case .hidOutput(let output) = $0, output.reportID != 0x12 { output.bytes } else { nil }
    }
  }

  @Test
  func anInactiveMotionPlusIsActivatedByTheModeOfThePluggedExtensionThenIdentified() throws {
    driver.passthroughBase = "Nunchuk"
    _ = try feed([0x20, 0, 0, 0x02, 0, 0, 0xC8])
    let ack: [UInt8] = [0x22, 0, 0, 0x16, 0]
    let block = [0x80, 0x80, 0x80, 0, 0xC0, 0xC0, 0xC0, 0, 0, 0] as [UInt8]
    _ = try feed([0x21, 0, 0, 9 << 4, 0x00, 0x16] + block + [0, 0, 0, 0, 0, 0])
    _ = try feed(ack)
    _ = try feed(ack)
    let id: [UInt8] = [0, 0, 0xA6, 0x20, 0x00, 0x05]
    let writes = try feed([0x21, 0, 0, 5 << 4, 0x00, 0xFA] + id + [UInt8](repeating: 0, count: 10))
    // The first activation write is 0x55 to 0xA600F0, then the nunchuk mode byte to 0xA600FE.
    #expect(writes.first?[0..<6] == [0x16, 0x04, 0xA6, 0x00, 0xF0, 0x01])
    #expect(writes.first?[6] == 0x55)
    let mode = try feed(ack)
    #expect(mode.first?[0..<7] == [0x16, 0x04, 0xA6, 0x00, 0xFE, 0x01, 0x05])
    let identify = try feed(ack)
    #expect(identify.first?[0..<7] == [0x17, 0x04, 0xA4, 0x00, 0xFA, 0x00, 0x06])
    let plus: [UInt8] = [0, 0, 0xA4, 0x20, 0x05, 0x05]
    _ = try feed([0x21, 0, 0, 5 << 4, 0x00, 0xFA] + plus + [UInt8](repeating: 0, count: 10))
    #expect(driver.extensionKind == .known("MotionPlusNunchuk"))
    #expect(driver.failure == nil)
  }
}
