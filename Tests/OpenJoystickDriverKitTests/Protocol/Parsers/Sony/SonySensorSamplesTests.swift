import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct SonySensorSamplesTests {
  @Test
  func clockPreservesFractionsWrapsAndRepeatedSamples() {
    var clock = SonySensorClock(mask: 0xFFFF, tickNumerator: 16_000)
    // The first receipt anchors the session; later receipt times do not move it.
    #expect(clock.timestamp(65_535, receivedAt: 7).monotonic.nanoseconds == 7)
    #expect(clock.timestamp(0, receivedAt: 50).monotonic.nanoseconds == 7 + 5333)
    #expect(clock.timestamp(1, receivedAt: 7).monotonic.nanoseconds == 7 + 10_666)
    let third = clock.timestamp(2, receivedAt: 7)
    #expect(third.monotonic.nanoseconds == 7 + 16_000)
    #expect(third.sequenceIndex == 3)
    let repeated = clock.timestamp(2, receivedAt: 7)
    #expect(repeated.monotonic.nanoseconds == 7 + 16_000)
    #expect(repeated.sequenceIndex == 4)
    var dualSense = SonySensorClock(mask: .max, tickNumerator: 1000)
    _ = dualSense.timestamp(.max, receivedAt: 9)
    #expect(dualSense.timestamp(2, receivedAt: 99).monotonic.nanoseconds == 9 + 1000)
  }

  @Test
  func dualSenseUSBDecodesSignedVectorsAndBothContacts() throws {
    var report = [UInt8](repeating: 0, count: 64)
    report[0] = 1
    report[8] = 8
    report.replaceSubrange(16..<28, with: [0, 128, 255, 127, 255, 255, 1, 0, 0, 255, 0, 1])
    report.replaceSubrange(28..<32, with: [0xFE, 0xFF, 0xFF, 0xFF])
    report.replaceSubrange(33..<41, with: [5, 0x34, 0xA2, 0x12, 0x87, 1, 0, 0])
    let parser = DualSenseDriver()
    let events = try parser.parseReport(Data(report))
    let motion = try #require(events?.motion.first)
    // Raw gyro (-32768, 32767, -1) and accel (1, -256, 256) at nominal scale, as (x, -z, y).
    #expect(isClose(motion.angularVelocity, radiansPerSecond(-2048, 1.0 / 16, 32_767.0 / 16)))
    #expect(
      isClose(motion.acceleration, metresPerSecondSquared(1.0 / 8192, -256.0 / 8192, -256.0 / 8192))
    )
    #expect(motion.timestamp.rawCounter == 0xFFFF_FFFE)
    let touch = try #require(events?.touchFrames.first)
    // Raw (564, 298) and (1, 0) on 1920x1080: round(raw * 65535 / (span - 1)). The tracking IDs
    // 5 and 7 are not slots; slots follow wire order.
    #expect(
      touch.contacts == [
        ControllerTouchContact(slot: 0, isActive: true, x: 19_261, y: 18_100),
        ControllerTouchContact(slot: 1, isActive: false, x: 34, y: 0),
      ]
    )
    #expect(touch.timestamp == motion.timestamp.monotonic)
    report.replaceSubrange(28..<32, with: [1, 0, 0, 0])
    let next = try parser.parseReport(Data(report))
    let wrapped = try #require(next?.motion.first)
    #expect(wrapped.timestamp.monotonic.nanoseconds == 1000)
    #expect(next?.motion.count == 1 && next?.touchFrames.count == 1)
    #expect(next?.state.pressed == events?.state.pressed && next?.state.hat == events?.state.hat)
  }

  @Test
  func dualShock4HistoryIsOrderedAndMalformedHistoryDoesNotLoseMotion() throws {
    var report = [UInt8](repeating: 0, count: 64)
    report[0] = 1
    report[5] = 8
    report[13] = 0xFE
    report[14] = 0xFF
    report[33] = 3
    for index in 0..<3 { report[36 + index * 9] = UInt8(index * 100) }
    let parser = DualShock4Driver()
    let events = try parser.parseReport(Data(report))
    let touches = (events?.touchFrames ?? [])
    // Raw X 0, 100, 200 on a 1920-wide pad keep wire order and share the report's time.
    #expect(touches.map { $0.contacts[0].x } == [0, 3415, 6830])
    let motion = try #require(events?.motion.first)
    #expect(touches.allSatisfy { $0.timestamp == motion.timestamp.monotonic })
    #expect(isClose(motion.angularVelocity, radiansPerSecond(-2.0 / 16, 0, 0)))
    report[33] = 4
    let malformed = try parser.parseReport(Data(report))
    // Malformed touch history must preserve the valid motion sample.
    #expect(malformed?.motion.count == 1)
    #expect(malformed?.touchFrames.isEmpty == true)
  }

  @Test
  func dualShock4BluetoothRetainsFourthHistoryFrame() throws {
    var report = [UInt8](repeating: 0, count: 78)
    report[0] = 0x11
    report[1] = 0xC0
    report[7] = 8
    report[35] = 4
    for index in 0..<4 {
      report[36 + index * 9] = UInt8(20 + index)
      report[37 + index * 9] = UInt8(index)
      report[38 + index * 9] = UInt8(index * 60)
    }
    var framed = [UInt8(0xA1)] + report
    applyDS4BluetoothInputCRC(to: &framed, includesHIDTransaction: true)
    let events = try DualShock4Driver().parseReport(Data(framed))
    let touches = (events?.touchFrames ?? [])
    #expect(touches.map { $0.contacts[0].x } == [0, 2049, 4098, 6147])
    // Tracking IDs 0...3 do not change the slot.
    #expect(touches.allSatisfy { $0.contacts.map(\.slot) == [0, 1] })
  }

  @Test
  func touchpadEdgesMapToTheFullRangeWithTopAtZero() throws {
    // DS4 1920x942 and DualSense 1920x1080: the first raw position is 0, the last is 65535, the
    // raw 12-bit overflow clamps, and raw Y grows downward, so the top edge is Y 0.
    #expect(
      dualShock4Contact(x: 0, y: 0) == ControllerTouchContact(slot: 0, isActive: true, x: 0, y: 0)
    )
    #expect(dualShock4Contact(x: 1919, y: 941)?.x == 65_535)
    #expect(dualShock4Contact(x: 1919, y: 941)?.y == 65_535)
    #expect(
      dualShock4Contact(x: 4095, y: 4095)
        == ControllerTouchContact(slot: 0, isActive: true, x: 65_535, y: 65_535)
    )
    #expect(
      dualShock4Contact(x: 960, y: 471)
        == ControllerTouchContact(slot: 0, isActive: true, x: 32_785, y: 32_802)
    )
    let dualSense = SonySensorSamples.dualSenseTouchpad
    #expect(
      dualSense.contact(slot: 1, isActive: false, rawX: 1919, rawY: 1079)
        == ControllerTouchContact(slot: 1, isActive: false, x: 65_535, y: 65_535)
    )
    #expect(
      dualSense.contact(slot: 0, isActive: true, rawX: 0, rawY: 540)
        == ControllerTouchContact(slot: 0, isActive: true, x: 0, y: 32_798)
    )
  }

  /// Decodes one DS4 USB touch frame whose first contact has the given raw coordinates.
  private func dualShock4Contact(x: UInt16, y: UInt16) -> ControllerTouchContact? {
    var report = [UInt8](repeating: 0, count: 64)
    report[0] = 1
    report[5] = 8
    report[33] = 1
    report[35] = 0x7F
    report[36] = UInt8(x & 0xFF)
    report[37] = UInt8(x >> 8 & 0x0F) | UInt8(y & 0x0F) << 4
    report[38] = UInt8(y >> 4 & 0xFF)
    return (try? DualShock4Driver().parseReport(Data(report)))?.touchFrames.first?.contacts.first
  }

  @Test
  func shortDualShock4ControlReportsDoNotInventSensorSamples() throws {
    let report = Data([1, 128, 128, 128, 128, 8, 0, 0, 0, 0])
    let event = try DualShock4Driver().parseReport(report)
    #expect(event?.state == .neutral)
    #expect(event?.motion.isEmpty == true && event?.touchFrames.isEmpty == true)
  }
}
