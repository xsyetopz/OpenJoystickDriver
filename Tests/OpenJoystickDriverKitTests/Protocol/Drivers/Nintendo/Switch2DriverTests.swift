import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Reports and command replies in the layout of SDL `SDL_hidapi_switch2.c` and the Switch 2
/// command notes it follows. They come from the source, not from a hardware capture.
private enum Switch2Report {
  static func state(
    buttons: UInt32 = 0,
    left: (UInt16, UInt16) = (2048, 2048),
    right: (UInt16, UInt16) = (2048, 2048),
    triggers: (UInt8, UInt8) = (0, 0)
  ) -> Data {
    var bytes = [UInt8](repeating: 0, count: 64)
    bytes[0] = 0x05
    for index in 0..<4 { bytes[5 + index] = UInt8(truncatingIfNeeded: buttons >> (index * 8)) }
    bytes.replaceSubrange(11..<14, with: pair(left.0, left.1))
    bytes.replaceSubrange(14..<17, with: pair(right.0, right.1))
    (bytes[61], bytes[62]) = triggers
    return Data(bytes)
  }

  static func pair(_ x: UInt16, _ y: UInt16) -> [UInt8] {
    [
      UInt8(truncatingIfNeeded: x), UInt8(truncatingIfNeeded: (x >> 8) & 0x0F | (y & 0x0F) << 4),
      UInt8(truncatingIfNeeded: y >> 4),
    ]
  }

  /// Neutral, max, and min pairs with the same value on both axes.
  static func calibration(neutral: UInt16, max: UInt16, min: UInt16) -> [UInt8] {
    pair(neutral, neutral) + pair(max, max) + pair(min, min)
  }

  /// A flash read reply: the 16-byte header with the address, then 64 data bytes.
  static func flashReply(address: UInt32, data: [Int: [UInt8]]) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: 0x50)
    bytes.replaceSubrange(0..<9, with: [0x02, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x40])
    for index in 0..<4 { bytes[12 + index] = UInt8(truncatingIfNeeded: address >> (index * 8)) }
    for (offset, values) in data {
      bytes.replaceSubrange((16 + offset)..<(16 + offset + values.count), with: values)
    }
    return bytes
  }
}

@Suite
struct Switch2DriverTests {

  @Test
  func mapsProButtonBitsAsSDLReportsThem() throws {
    let cases: [(UInt32, ControlID)] = [
      (0x0000_0001, .faceWest), (0x0000_0002, .faceNorth), (0x0000_0004, .faceSouth),
      (0x0000_0008, .faceEast), (0x0000_0040, .rightShoulder), (0x0000_0080, .rightTriggerButton),
      (0x0000_0100, .view), (0x0000_0200, .menu), (0x0000_0400, .rightStickClick),
      (0x0000_0800, .leftStickClick), (0x0000_1000, .guide), (0x0000_2000, .capture),
      (0x0000_4000, .auxiliary1), (0x0040_0000, .leftShoulder), (0x0080_0000, .leftTriggerButton),
      (0x0100_0000, .paddleRight1), (0x0200_0000, .paddleLeft1),
    ]
    for (mask, control) in cases {
      let driver = Switch2Driver(layout: .pro)
      #expect(try driver.parseReport(Switch2Report.state(buttons: mask)).contains(.press(control)))
      #expect(try driver.parseReport(Switch2Report.state()).contains(.release(control)))
    }
  }

  @Test
  func decodesTheDPadBitsIntoTheHat() throws {
    let cases: [(UInt32, HatDirection)] = [
      (0x02, .north), (0x06, .northEast), (0x04, .east), (0x05, .southEast), (0x01, .south),
      (0x09, .southWest), (0x08, .west), (0x0A, .northWest), (0x03, .neutral),
    ]
    for (bits, direction) in cases {
      let report = Switch2Report.state(buttons: bits << 16)
      #expect(try Switch2Driver().parseReport(report)?.state.hat == direction)
    }
  }

  @Test
  func joyConHalvesUseTheirSideAndSideRailButtons() throws {
    let left = Switch2Driver(layout: .leftJoyCon)
    let leftEvent = try #require(
      try left.parseReport(Switch2Report.state(buttons: 0x0030_0100, left: (3072, 2048)))
    )
    #expect(leftEvent.state.pressed == [.view, .auxiliary3, .auxiliary4])
    #expect(leftEvent.state.leftStick == StickPosition(x: 0.5, yDown: 0))
    #expect(leftEvent.state.rightStick == StickPosition(x: 0, yDown: 0))

    let right = Switch2Driver(layout: .rightJoyCon)
    let rightEvent = try #require(
      try right.parseReport(Switch2Report.state(buttons: 0x0001_4034, right: (0, 2048)))
    )
    #expect(rightEvent.state.pressed == [.faceSouth, .auxiliary5, .auxiliary6, .auxiliary1])
    #expect(rightEvent.state.hat == .neutral)
    #expect(rightEvent.state.rightStick.x == .min)
    #expect(!right.capabilities.controls.contains(.paddleRight1))
  }

  @Test
  func sticksUseFlashCalibrationWithUserValuesWinning() throws {
    let driver = Switch2Driver(layout: .pro)
    // Without calibration, SDL maps 0...4096 onto -1...1.
    let raw = try #require(try driver.parseReport(Switch2Report.state(left: (3072, 1024))))
    #expect(raw.state.leftStick == StickPosition(x: 0.5, yDown: 0.5))

    let factory = Switch2Report.calibration(neutral: 2048, max: 1000, min: 1000)
    driver.consumeUSBCommandReply(Switch2Report.flashReply(address: 0x13080, data: [0x28: factory]))
    let calibrated = try #require(try driver.parseReport(Switch2Report.state(left: (3048, 1548))))
    #expect(calibrated.state.leftStick == StickPosition(x: 1, yDown: 0.5))

    // User calibration applies only with the `b2 a1` marker.
    let user = Switch2Report.calibration(neutral: 2548, max: 500, min: 500)
    driver.consumeUSBCommandReply(Switch2Report.flashReply(address: 0x1FC040, data: [2: user]))
    let unmarked = try #require(try driver.parseReport(Switch2Report.state(left: (3048, 2048))))
    #expect(unmarked.state.leftStick.x == .max)
    driver.consumeUSBCommandReply(
      Switch2Report.flashReply(address: 0x1FC040, data: [0: [0xB2, 0xA1], 2: user])
    )
    let marked = try #require(try driver.parseReport(Switch2Report.state(left: (2548, 2048))))
    #expect(marked.state.leftStick == StickPosition(x: 0, yDown: 1))

    // Replies to other commands leave the calibration alone.
    var other = Switch2Report.flashReply(address: 0x13080, data: [0x28: user])
    other[3] = 0x02
    driver.consumeUSBCommandReply(other)
    #expect(
      try driver.parseReport(Switch2Report.state(left: (2548, 2048)))?.state.leftStick.x == .center
    )
  }

  /// SDL reads a solo right Joy-Con's stick with the primary calibration slot.
  @Test
  func rightJoyConReadsThePrimaryCalibrationSlot() throws {
    let driver = Switch2Driver(layout: .rightJoyCon)
    let calibration = Switch2Report.calibration(neutral: 1048, max: 1000, min: 1000)
    driver.consumeUSBCommandReply(
      Switch2Report.flashReply(address: 0x130C0, data: [0x28: calibration])
    )
    #expect(
      try driver.parseReport(Switch2Report.state(right: (1048, 2048)))?.state.rightStick.x
        != .center
    )
    driver.consumeUSBCommandReply(
      Switch2Report.flashReply(address: 0x13080, data: [0x28: calibration])
    )
    #expect(
      try driver.parseReport(Switch2Report.state(right: (1048, 2048)))?.state.rightStick.x
        == .center
    )
  }

  @Test
  func gameCubeTriggersScaleFromTheFlashZeroPoint() throws {
    let driver = Switch2Driver(layout: .gameCube)
    driver.consumeUSBCommandReply(Switch2Report.flashReply(address: 0x13140, data: [0: [32, 32]]))
    let report = Switch2Report.state(buttons: 0x0000_0080 | 0x0080_0000, triggers: (132, 240))
    let event = try #require(try driver.parseReport(report))
    #expect(event.state.leftTrigger == UnipolarValue(normalized: 0.5))
    #expect(event.state.rightTrigger == .max)
    #expect(event.state.pressed == [.rightShoulder, .leftShoulder])
  }

  @Test
  func rejectsShortReportsAndOtherReportIDs() throws {
    var other = Array(Switch2Report.state(buttons: 1))
    other[0] = 0x09
    #expect(try Switch2Driver().parseReport(Data(other)) == nil)
    #expect(try Switch2Driver().parseReport(Switch2Report.state(buttons: 1).prefix(63)) == nil)
  }

  @Test
  func startupReadsCalibrationThenRunsTheInitSequence() {
    let pro = Switch2Driver(layout: .pro).startupWrites().usbPackets
    #expect(pro.count == 14)
    #expect(pro.allSatisfy { $0.endpoint == 0x02 })
    #expect(
      pro[0].bytes == [0x02, 0x91, 0x00, 0x01, 0x00, 0x08, 0, 0, 0, 0, 0, 0, 0x80, 0x30, 0x01, 0]
    )
    #expect(pro.suffix(10).allSatisfy { $0.bytes.count == Int($0.bytes[5]) + 8 })
    #expect(pro.last?.bytes.prefix(4) == [0x03, 0x91, 0x00, 0x0D])

    let gameCube = Switch2Driver(layout: .gameCube).startupWrites().usbPackets
    #expect(gameCube.count == 15)
    #expect(gameCube[2].bytes.suffix(4) == [0x40, 0x31, 0x01, 0x00])

    let plan = Switch2Driver().sessionPlan
    #expect(plan.usbCommandChannel?.interfaceNumber == 1)
    #expect(plan.usbCommandChannel?.inEndpoint == 0x82)
    #expect(plan.hidKeepAliveIntervalNanoseconds == 12_000_000)
  }

  @Test
  func bluetoothLELinkMarksEveryCommandAndSendsTheConsoleInitSequence() {
    let driver = Switch2Driver(layout: .pro, link: .bluetoothLE)
    let packets = driver.startupWrites().usbPackets
    #expect(packets.count == 9)
    #expect(packets.allSatisfy { $0.bytes[2] == 0x01 })
    #expect(packets[0].bytes.suffix(4) == [0x80, 0x30, 0x01, 0x00])
    #expect(
      packets.suffix(5).map { [$0.bytes[0], $0.bytes[3]] } == [
        [0x07, 0x01], [0x0C, 0x02], [0x11, 0x01], [0x0A, 0x08], [0x0C, 0x04],
      ]
    )
    #expect(driver.encoded(.setPlayerIndicator(.player1)).onlyPacket.bytes[2] == 0x01)
    #expect(driver.sessionPlan.usbCommandChannel?.replyTimeoutMilliseconds == 500)
    #expect(Switch2Driver().sessionPlan.usbCommandChannel?.replyTimeoutMilliseconds == 100)
  }

  @Test
  func playerIndicatorTravelsOnTheCommandChannel() {
    let packet = Switch2Driver().encoded(.setPlayerIndicator(.player2)).onlyPacket
    #expect(packet.endpoint == 0x02)
    #expect(packet.bytes == [0x09, 0x91, 0x00, 0x07, 0x00, 0x08, 0, 0, 0x03, 0, 0, 0, 0, 0, 0, 0])
  }

  @Test
  func proRumbleEncodesHDRumbleForBothActuators() {
    let driver = Switch2Driver(layout: .pro)
    let full = RumbleIntensities(leftMain: .max, rightMain: .max)
    let report = driver.encoded(.setRumble(full, duration: .milliseconds(100))).onlyReport
    #expect(report.reportID == 0x02 && report.bytes.count == 64)
    let expected: [UInt8] = [0x50, 0x87, 0x15, 0x27, 0x51, 0x71]
    #expect(Array(report.bytes[1..<7]) == expected)
    #expect(Array(report.bytes[0x11..<0x17]) == expected)

    let joyCon = Switch2Driver(layout: .leftJoyCon).encoded(.stopRumble).onlyReport
    #expect(joyCon.reportID == 0x01)
    #expect(Array(joyCon.bytes[1..<7]) == [0x50, 0x87, 0x01, 0x20, 0x11, 0x00])
    #expect(joyCon.bytes[0x11] == 0)
  }

  @Test
  func rumbleRefreshRunsWhileActiveAndSendsTrailingStops() {
    let driver = Switch2Driver(layout: .pro)
    #expect(driver.keepAliveWrites().isEmpty)
    let half = RumbleIntensities(leftMain: UnipolarValue(0x8000), rightMain: .min)
    _ = driver.encoded(.setRumble(half, duration: .milliseconds(100)))
    let sequences = (0..<3).map { _ in driver.keepAliveWrites().hidOutputs.first?.bytes[1] }
    #expect(sequences == [0x51, 0x52, 0x53])

    _ = driver.encoded(.stopRumble)
    #expect(driver.keepAliveWrites().hidOutputs.count == 1)
    #expect(driver.keepAliveWrites().hidOutputs.count == 1)
    #expect(driver.keepAliveWrites().isEmpty)
  }

  /// SDL `UpdateRumble` for the GameCube controller: on, off, or stop, dithered by an error sum.
  @Test
  func gameCubeRumbleDithersItsSingleMotor() {
    let driver = Switch2Driver(layout: .gameCube)
    let half = RumbleIntensities(leftMain: .min, rightMain: UnipolarValue(0x8000))
    let first = driver.encoded(.setRumble(half, duration: .milliseconds(100))).onlyReport
    #expect(first.reportID == 0x03)
    let states =
      [first.bytes[2]]
      + (0..<3).compactMap { _ in driver.keepAliveWrites().hidOutputs.first?.bytes[2] }
    #expect(states == [1, 1, 0, 1])
    #expect(driver.encoded(.stopRumble).onlyReport.bytes[2] == 2)
  }
}
