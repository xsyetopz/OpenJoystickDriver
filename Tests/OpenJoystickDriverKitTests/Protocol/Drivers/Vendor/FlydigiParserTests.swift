import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Reports captured from a Flydigi Vader 4 Pro over Bluetooth Low Energy,
/// firmware 6.9.5.5, on macOS 26.5.
private enum CapturedReport {
  static let neutral: [UInt8] = [
    0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
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

private func settled(_ parser: ReportLayoutDriver) {
  _ = try? parser.parseReport(Data(CapturedReport.neutral))
}

@Suite
struct FlydigiParserTests {
  static let family = PhysicalProtocolID.vendorFlydigi
  static let model = ControllerModelID(vendorID: 0xD7D7, productID: 0x0041)

  @Test(arguments: [0, 1, 2])
  func malformedReportsPreserveState(kind: Int) throws {
    let parser = flydigiDriver()
    let pressed = CapturedReport.with(hatAndFace: 0x10)
    #expect(try parser.parseReport(pressed).contains(.press(.south)))
    var malformed = Data(CapturedReport.neutral)
    switch kind {
    case 0: malformed[0] = 0x02
    case 1: malformed.removeLast()
    default: malformed.append(0)
    }
    #expect(try parser.parseReport(malformed) == nil)
    #expect(try parser.parseReport(pressed).contains(.press(.south)))
    #expect(try parser.parseReport(Data(CapturedReport.neutral)).contains(.release(.south)))
  }

  @Test
  func testNeutralReportKeepsRestingStickOffsetWithoutDriverDeadzone() throws {
    let parser = flydigiDriver()
    settled(parser)
    let rest = BipolarValue(normalized: Float(-1) / 127)
    var expected = ControllerState.neutral
    expected.leftStick = StickPosition(x: rest, y: rest)
    expected.rightStick = expected.leftStick
    #expect(try parser.parseReport(Data(CapturedReport.neutral))?.state == expected)
  }

  @Test
  func testShortReportIsIgnored() throws {
    let parser = flydigiDriver()
    #expect(try parser.parseReport(Data([0x01, 0xFF, 0xFF])) == nil)
  }

  /// The hardware reports 0x80 when the stick is pushed fully up, so the
  /// normalized value stays negative and is not flipped.
  @Test
  func testLeftStickUpIsNegativeY() throws {
    let parser = flydigiDriver()
    settled(parser)
    let events = try parser.parseReport(CapturedReport.with(leftStickY: 0x80))
    #expect((events.leftStickPosition?.y ?? 0) < -0.9)
  }

  @Test
  func testLeftStickRightIsPositiveX() throws {
    let parser = flydigiDriver()
    settled(parser)
    let events = try parser.parseReport(CapturedReport.with(leftStickX: 0x7F))
    #expect((events.leftStickPosition?.x ?? 0) > 0.9)
  }

  /// Bytes 3 and 4 are the right stick, not the triggers the descriptor implies.
  @Test
  func testRightStickUsesZAndRzBytes() throws {
    let parser = flydigiDriver()
    settled(parser)
    let events = try parser.parseReport(CapturedReport.with(rightStickX: 0x7F, rightStickY: 0x80))
    let stick = try #require(events.rightStickPosition)
    #expect(stick.x > 0.9 && stick.y < -0.9)
  }

  @Test
  func testRightStickDeflectionLeavesTheTriggersReleased() throws {
    let parser = flydigiDriver()
    settled(parser)
    let events = try parser.parseReport(CapturedReport.with(rightStickX: 0x7F))
    #expect(events?.state.leftTrigger == .min && events?.state.rightTrigger == .min)
  }

  @Test
  func testAnalogTriggersUseSimulationBytes() throws {
    let parser = flydigiDriver()
    settled(parser)
    let left = try parser.parseReport(CapturedReport.with(shoulders: 0x04, leftTrigger: 0xFF))
    #expect(left.contains(.leftTrigger(1.0)))

    settled(parser)
    let right = try parser.parseReport(CapturedReport.with(shoulders: 0x08, rightTrigger: 0xFF))
    #expect(right.contains(.rightTrigger(1.0)))
  }

  /// The digital trigger bit accompanies the analog value and must not be
  /// reported as a stick click.
  @Test
  func testDigitalTriggerBitIsNotAStickClick() throws {
    let parser = flydigiDriver()
    settled(parser)
    let events = try parser.parseReport(CapturedReport.with(shoulders: 0x04, leftTrigger: 0xFF))
    #expect(events.contains(.release(.leftStickClick)))
  }

  @Test
  func testFaceButtonsUseHighNibble() throws {
    let cases: [(UInt8, Control)] = [
      (0x10, .south), (0x20, .east), (0x40, .west), (0x80, .north),
    ]
    for (mask, button) in cases {
      let parser = flydigiDriver()
      settled(parser)
      let events = try parser.parseReport(CapturedReport.with(hatAndFace: mask))
      #expect(events.contains(.press(button)))
    }
  }

  @Test
  func testShoulderByteButtons() throws {
    let cases: [(UInt8, Control)] = [
      (0x01, .leftShoulder), (0x02, .rightShoulder), (0x10, .back), (0x20, .start),
      (0x40, .leftStickClick), (0x80, .rightStickClick),
    ]
    for (mask, button) in cases {
      let parser = flydigiDriver()
      settled(parser)
      let events = try parser.parseReport(CapturedReport.with(shoulders: mask))
      #expect(events.contains(.press(button)))
    }
  }

  /// The order of the four back buttons is a proposal until a tester names them.
  @Test(arguments: [
    (UInt8(0x01), Control.auxiliary1), (0x02, .auxiliary2), (0x04, .leftPaddle1),
    (0x08, .leftPaddle2), (0x10, .rightPaddle1), (0x20, .rightPaddle2),
  ])
  func testByteElevenButtonsPressAndRelease(mask: UInt8, button: Control) throws {
    let parser = flydigiDriver()
    settled(parser)
    let pressed = try parser.parseReport(CapturedReport.with(extras: mask))
    #expect(pressed.contains(.press(button)))
    #expect(pressed?.state.pressed == [button])
    #expect(try parser.parseReport(Data(CapturedReport.neutral)).contains(.release(button)))
  }

  @Test
  func testGuideUsesSystemByte() throws {
    let parser = flydigiDriver()
    settled(parser)
    let events = try parser.parseReport(CapturedReport.with(system: 0x80))
    #expect(events.contains(.press(.guide)))
  }

  /// The D-pad is a 4-bit hat in the low nibble, clockwise from 1 = up.
  @Test
  func testHatDirections() throws {
    let cases: [(UInt8, HatDirection)] = [
      (1, .north), (3, .east), (5, .south), (7, .west), (0, .neutral),
    ]
    for (value, direction) in cases {
      let parser = flydigiDriver()
      _ = try parser.parseReport(CapturedReport.with(hatAndFace: 2))
      let events = try parser.parseReport(CapturedReport.with(hatAndFace: value))
      #expect(events.contains(.hat(direction)))
    }
  }

  /// The hat shares its byte with the face buttons, so one must not disturb
  /// the other.
  @Test
  func testHatAndFaceButtonCoexist() throws {
    let parser = flydigiDriver()
    settled(parser)
    let events = try parser.parseReport(CapturedReport.with(hatAndFace: 0x10 | 3))
    #expect(events.contains(.press(.south)))
    #expect(events.contains(.hat(.east)))
  }

  @Test
  func testButtonReleaseEmitsReleaseEvent() throws {
    let parser = flydigiDriver()
    settled(parser)
    _ = try parser.parseReport(CapturedReport.with(hatAndFace: 0x10))
    let events = try parser.parseReport(Data(CapturedReport.neutral))
    #expect(events.contains(.release(.south)))
  }

  @Test
  func testRepeatedReportRepeatsTheSnapshot() throws {
    let parser = flydigiDriver()
    settled(parser)
    let first = try parser.parseReport(CapturedReport.with(hatAndFace: 0x10))
    #expect(try parser.parseReport(CapturedReport.with(hatAndFace: 0x10))?.state == first?.state)
  }

  @Test
  func testRestingAxisJitterPassesThroughWithoutDriverDeadzone() throws {
    func axis(_ raw: UInt8) throws -> BipolarValue {
      let event = try flydigiDriver().parseReport(CapturedReport.with(leftStickX: raw))
      return try #require(event?.state.leftStick.x)
    }
    #expect(try axis(0xFF) == BipolarValue(normalized: Float(-1) / 127))
    #expect(try axis(0x01) == BipolarValue(normalized: Float(1) / 127))
    #expect(try axis(0x00) == BipolarValue(normalized: 0))
    #expect(try axis(0x7F).normalized > 0.9)
    #expect(try axis(0x80).normalized < -0.9)
  }
}
