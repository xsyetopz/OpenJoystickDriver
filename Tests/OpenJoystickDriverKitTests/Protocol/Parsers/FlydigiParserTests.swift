import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Reports captured from a Flydigi Vader 4 Pro over Bluetooth Low Energy,
/// firmware 6.9.5.5, on macOS 26.5.
private enum CapturedReport {
  static let neutral: [UInt8] = [
    0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
  ]

  static func with(
    leftStickX: UInt8 = 0xFF,
    leftStickY: UInt8 = 0xFF,
    rightStickX: UInt8 = 0xFF,
    rightStickY: UInt8 = 0xFF,
    hatAndFace: UInt8 = 0,
    shoulders: UInt8 = 0,
    extras: UInt8 = 0,
    system: UInt8 = 0,
    leftTrigger: UInt8 = 0,
    rightTrigger: UInt8 = 0
  ) -> Data {
    var report = neutral
    report[1] = leftStickX
    report[2] = leftStickY
    report[3] = rightStickX
    report[4] = rightStickY
    report[9] = hatAndFace
    report[10] = shoulders
    report[11] = extras
    report[12] = system
    report[13] = leftTrigger
    report[14] = rightTrigger
    return Data(report)
  }
}

private func settled(_ parser: FlydigiParser) {
  _ = try? parser.parse(data: Data(CapturedReport.neutral))
}

@Suite struct FlydigiParserTests {

  @Test func testNeutralReportEmitsNoEvents() throws {
    let parser = FlydigiParser()
    settled(parser)
    #expect(try parser.parse(data: Data(CapturedReport.neutral)).isEmpty)
  }

  @Test func testShortReportIsIgnored() throws {
    let parser = FlydigiParser()
    #expect(try parser.parse(data: Data([0x01, 0xFF, 0xFF])).isEmpty)
  }

  /// The hardware reports 0x80 when the stick is pushed fully up, so the
  /// normalized value stays negative and is not flipped.
  @Test func testLeftStickUpIsNegativeY() throws {
    let parser = FlydigiParser()
    settled(parser)
    let events = try parser.parse(data: CapturedReport.with(leftStickY: 0x80))
    #expect(events.contains { event in
      if case .leftStickChanged(_, let y) = event { return y < -0.9 }
      return false
    })
  }

  @Test func testLeftStickRightIsPositiveX() throws {
    let parser = FlydigiParser()
    settled(parser)
    let events = try parser.parse(data: CapturedReport.with(leftStickX: 0x7F))
    #expect(events.contains { event in
      if case .leftStickChanged(let x, _) = event { return x > 0.9 }
      return false
    })
  }

  /// Bytes 3 and 4 are the right stick, not the triggers the descriptor implies.
  @Test func testRightStickUsesZAndRzBytes() throws {
    let parser = FlydigiParser()
    settled(parser)
    let events = try parser.parse(data: CapturedReport.with(rightStickX: 0x7F, rightStickY: 0x80))
    #expect(events.contains { event in
      if case .rightStickChanged(let x, let y) = event { return x > 0.9 && y < -0.9 }
      return false
    })
  }

  @Test func testRightStickDeflectionEmitsNoTriggerEvent() throws {
    let parser = FlydigiParser()
    settled(parser)
    let events = try parser.parse(data: CapturedReport.with(rightStickX: 0x7F))
    #expect(!events.contains { event in
      if case .leftTriggerChanged = event { return true }
      if case .rightTriggerChanged = event { return true }
      return false
    })
  }

  @Test func testAnalogTriggersUseSimulationBytes() throws {
    let parser = FlydigiParser()
    settled(parser)
    let left = try parser.parse(data: CapturedReport.with(shoulders: 0x04, leftTrigger: 0xFF))
    #expect(left.contains { $0 == .leftTriggerChanged(1.0) })

    settled(parser)
    let right = try parser.parse(data: CapturedReport.with(shoulders: 0x08, rightTrigger: 0xFF))
    #expect(right.contains { $0 == .rightTriggerChanged(1.0) })
  }

  /// The digital trigger bit accompanies the analog value and must not be
  /// reported as a stick click.
  @Test func testDigitalTriggerBitIsNotAStickClick() throws {
    let parser = FlydigiParser()
    settled(parser)
    let events = try parser.parse(data: CapturedReport.with(shoulders: 0x04, leftTrigger: 0xFF))
    #expect(!events.contains { $0 == .buttonPressed(.leftStick) })
  }

  @Test func testFaceButtonsUseHighNibble() throws {
    let cases: [(UInt8, Button)] = [(0x10, .a), (0x20, .b), (0x40, .x), (0x80, .y)]
    for (mask, button) in cases {
      let parser = FlydigiParser()
      settled(parser)
      let events = try parser.parse(data: CapturedReport.with(hatAndFace: mask))
      #expect(events.contains { $0 == .buttonPressed(button) })
    }
  }

  @Test func testShoulderByteButtons() throws {
    let cases: [(UInt8, Button)] = [
      (0x01, .leftBumper), (0x02, .rightBumper), (0x10, .back), (0x20, .start),
      (0x40, .leftStick), (0x80, .rightStick)
    ]
    for (mask, button) in cases {
      let parser = FlydigiParser()
      settled(parser)
      let events = try parser.parse(data: CapturedReport.with(shoulders: mask))
      #expect(events.contains { $0 == .buttonPressed(button) })
    }
  }

  @Test func testGuideUsesSystemByte() throws {
    let parser = FlydigiParser()
    settled(parser)
    let events = try parser.parse(data: CapturedReport.with(system: 0x80))
    #expect(events.contains { $0 == .buttonPressed(.guide) })
  }

  /// The D-pad is a 4-bit hat in the low nibble, clockwise from 1 = up.
  @Test func testHatDirections() throws {
    let cases: [(UInt8, DpadDirection)] = [
      (1, .north), (3, .east), (5, .south), (7, .west), (0, .neutral)
    ]
    for (value, direction) in cases {
      let parser = FlydigiParser()
      _ = try parser.parse(data: CapturedReport.with(hatAndFace: 2))
      let events = try parser.parse(data: CapturedReport.with(hatAndFace: value))
      #expect(events.contains { $0 == .dpadChanged(direction) })
    }
  }

  /// The hat shares its byte with the face buttons, so one must not disturb
  /// the other.
  @Test func testHatAndFaceButtonCoexist() throws {
    let parser = FlydigiParser()
    settled(parser)
    let events = try parser.parse(data: CapturedReport.with(hatAndFace: 0x10 | 3))
    #expect(events.contains { $0 == .buttonPressed(.a) })
    #expect(events.contains { $0 == .dpadChanged(.east) })
  }

  @Test func testButtonReleaseEmitsReleaseEvent() throws {
    let parser = FlydigiParser()
    settled(parser)
    _ = try parser.parse(data: CapturedReport.with(hatAndFace: 0x10))
    let events = try parser.parse(data: Data(CapturedReport.neutral))
    #expect(events.contains { $0 == .buttonReleased(.a) })
  }

  @Test func testRepeatedReportEmitsNoDuplicateEvents() throws {
    let parser = FlydigiParser()
    settled(parser)
    _ = try parser.parse(data: CapturedReport.with(hatAndFace: 0x10))
    #expect(try parser.parse(data: CapturedReport.with(hatAndFace: 0x10)).isEmpty)
  }

  @Test func testRestingAxisJitterStaysInDeadzone() {
    #expect(FlydigiParser.axis(0xFF) == 0)
    #expect(FlydigiParser.axis(0x00) == 0)
    #expect(FlydigiParser.axis(0x7F) > 0.9)
    #expect(FlydigiParser.axis(0x80) < -0.9)
  }
}
