import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct SonySensorSamplesTests {
  @Test func clockPreservesFractionsWrapsAndRepeatedSamples() {
    var clock = SonySensorClock(mask: 0xFFFF, tickNumerator: 16_000)
    #expect(clock.timestamp(65_535).elapsedNanoseconds == 0)
    #expect(clock.timestamp(0).elapsedNanoseconds == 5333)
    #expect(clock.timestamp(1).elapsedNanoseconds == 10_666)
    let third = clock.timestamp(2)
    #expect(third.elapsedNanoseconds == 16_000)
    #expect(third.sequenceIndex == 3)
    let repeated = clock.timestamp(2)
    #expect(repeated.elapsedNanoseconds == 16_000)
    #expect(repeated.sequenceIndex == 4)
    var dualSense = SonySensorClock(mask: .max, tickNumerator: 1000)
    _ = dualSense.timestamp(.max)
    #expect(dualSense.timestamp(2).elapsedNanoseconds == 1000)
  }

  @Test func dualSenseUSBDecodesSignedVectorsAndBothContacts() throws {
    var report = [UInt8](repeating: 0, count: 64)
    report[0] = 1
    report[8] = 8
    report.replaceSubrange(16..<28, with: [0, 128, 255, 127, 255, 255, 1, 0, 0, 255, 0, 1])
    report.replaceSubrange(28..<32, with: [0xFE, 0xFF, 0xFF, 0xFF])
    report.replaceSubrange(33..<41, with: [5, 0x34, 0xA2, 0x12, 0x87, 1, 0, 0])
    let parser = DualSenseParser()
    let events = try parser.parse(data: Data(report))
    let motion = try #require(events.compactMap { event -> ControllerMotionSample? in
      if case .motionSample(let sample) = event { return sample }
      return nil
    }.first)
    #expect(motion.rawGyroscope == ControllerRawSensorVector(x: -32_768, y: 32_767, z: -1))
    #expect(motion.rawAccelerometer == ControllerRawSensorVector(x: 1, y: -256, z: 256))
    #expect(motion.timestamp.rawCounter == 0xFFFF_FFFE)
    let touch = try #require(events.compactMap { event -> ControllerTouchSample? in
      if case .touchSample(let sample) = event { return sample }
      return nil
    }.first)
    #expect(touch.width == 1920 && touch.height == 1080)
    #expect(touch.contacts == [
      ControllerTouchContact(id: 5, isActive: true, x: 0x234, y: 0x12A),
      ControllerTouchContact(id: 7, isActive: false, x: 1, y: 0)
    ])
    #expect(touch.reportTimestamp == motion.timestamp)
    report.replaceSubrange(28..<32, with: [1, 0, 0, 0])
    let next = try parser.parse(data: Data(report))
    guard case .motionSample(let wrapped) = next.first else {
      Issue.record("Expected motion sample without repeated control transitions")
      return
    }
    #expect(wrapped.timestamp.elapsedNanoseconds == 1000)
    #expect(next.count == 2)
  }

  @Test func dualShock4HistoryIsOrderedAndMalformedHistoryDoesNotLoseMotion() throws {
    var report = [UInt8](repeating: 0, count: 64)
    report[0] = 1
    report[5] = 8
    report[13] = 0xFE
    report[14] = 0xFF
    report[33] = 3
    report[34] = 254
    report[43] = 255
    report[52] = 0
    let parser = DS4Parser()
    let events = try parser.parse(data: Data(report))
    let touches = events.compactMap { event -> ControllerTouchSample? in
      if case .touchSample(let sample) = event { return sample }
      return nil
    }
    #expect(touches.map(\.rawTouchCounter) == [254, 255, 0])
    #expect(touches.map(\.historyIndex) == [0, 1, 2])
    #expect(touches.allSatisfy { $0.width == 1920 && $0.height == 942 })
    let motion = try #require(events.compactMap { event -> ControllerMotionSample? in
      if case .motionSample(let sample) = event { return sample }
      return nil
    }.first)
    #expect(motion.rawGyroscope.x == -2)
    report[33] = 4
    let malformed = try parser.parse(data: Data(report))
    #expect(malformed.count == 1)
    guard case .motionSample = malformed.first else {
      Issue.record("Malformed touch history must preserve the valid motion sample")
      return
    }
  }

  @Test func dualShock4BluetoothRetainsFourthHistoryFrame() throws {
    var report = [UInt8](repeating: 0, count: 78)
    report[0] = 0x11
    report[1] = 0xC0
    report[7] = 8
    report[35] = 4
    for index in 0..<4 {
      report[36 + index * 9] = UInt8(20 + index)
      report[37 + index * 9] = UInt8(index)
    }
    let events = try DS4Parser().parse(data: Data([0xA1] + report))
    let touches = events.compactMap { event -> ControllerTouchSample? in
      if case .touchSample(let sample) = event { return sample }
      return nil
    }
    #expect(touches.map(\.rawTouchCounter) == [20, 21, 22, 23])
    #expect(touches.map(\.historyIndex) == [0, 1, 2, 3])
    #expect(touches.map { $0.contacts[0].id } == [0, 1, 2, 3])
  }

  @Test func shortDualShock4ControlReportsDoNotInventSensorSamples() throws {
    let report = Data([1, 128, 128, 128, 128, 8, 0, 0, 0, 0])
    #expect(try DS4Parser().parse(data: report) == [.dpadChanged(.neutral)])
  }
}
