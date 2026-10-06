import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Reports in SDL `SDL_hidapi_shield.c` layouts. V103 (16 bytes): buttons at 1, system at 2, hat at
/// 3, sticks at 4–11, triggers at 12–15. V104 (23+ bytes): hat at 2, buttons at 3, start at 4,
/// sticks at 9–16, guide/back at 17, triggers at 19–22. Axes are 16-bit LE centered on 0x8000.
private enum ShieldReport {
  static func v103(_ bytes: [Int: UInt8] = [:]) -> Data {
    report(length: 16, hat: 3, sticks: 4, bytes)
  }

  static func v104(_ bytes: [Int: UInt8] = [:]) -> Data {
    report(length: 32, hat: 2, sticks: 9, bytes)
  }

  private static func report(length: Int, hat: Int, sticks: Int, _ bytes: [Int: UInt8]) -> Data {
    var report = [UInt8](repeating: 0, count: length)
    report[0] = 0x01
    report[hat] = 0x08
    for offset in stride(from: sticks + 1, to: sticks + 8, by: 2) { report[offset] = 0x80 }
    for (offset, value) in bytes { report[offset] = value }
    return Data(report)
  }
}

/// A fresh driver per use: drivers keep the last parsed state.
private var v103: NVIDIAShieldDriver { NVIDIAShieldDriver(isShield2015: true) }
private var v104: NVIDIAShieldDriver { NVIDIAShieldDriver(isShield2015: false) }

@Suite
struct NVIDIAShieldDriverTests {

  @Test
  func restingReportsAreNeutral() throws {
    #expect(try v103.parseReport(ShieldReport.v103())?.state == .neutral)
    #expect(try v104.parseReport(ShieldReport.v104())?.state == .neutral)
  }

  @Test(arguments: [
    (1, 0x01, ControlID.faceSouth), (1, 0x02, .faceEast), (1, 0x04, .faceWest),
    (1, 0x08, .faceNorth), (1, 0x10, .leftShoulder), (1, 0x20, .rightShoulder),
    (1, 0x40, .leftStickClick), (1, 0x80, .rightStickClick), (2, 0x02, .menu), (2, 0x40, .view),
    (2, 0x80, .guide),
  ])
  func v103ButtonsFollowSDL(offset: Int, mask: UInt8, control: ControlID) throws {
    let event = try v103.parseReport(ShieldReport.v103([offset: mask]))
    #expect(event?.state == snapshot(.press(control)))
  }

  @Test(arguments: [
    (3, 0x01, ControlID.faceSouth), (3, 0x08, .faceNorth), (3, 0x80, .rightStickClick),
    (4, 0x01, .menu), (17, 0x01, .guide), (17, 0x02, .view),
  ])
  func v104ButtonsFollowSDL(offset: Int, mask: UInt8, control: ControlID) throws {
    let event = try v104.parseReport(ShieldReport.v104([offset: mask]))
    #expect(event?.state == snapshot(.press(control)))
  }

  @Test
  func hatCountsClockwiseFromUp() throws {
    #expect(try v103.parseReport(ShieldReport.v103([3: 0]))?.state == snapshot(.hat(.north)))
    #expect(try v103.parseReport(ShieldReport.v103([3: 3]))?.state == snapshot(.hat(.southEast)))
    #expect(try v104.parseReport(ShieldReport.v104([2: 6]))?.state == snapshot(.hat(.west)))
  }

  @Test
  func axesAreCenteredWordsAndTriggersRestAtZero() throws {
    let v103Event = try v103.parseReport(
      ShieldReport.v103([4: 0xFF, 5: 0xFF, 7: 0x00, 12: 0xFF, 13: 0xFF])
    )
    #expect(v103Event?.state == snapshot(.leftStick(x: 1, y: -1), .leftTrigger(1)))
    let v104Event = try v104.parseReport(
      ShieldReport.v104([15: 0xFF, 16: 0xFF, 21: 0xFF, 22: 0xFF])
    )
    #expect(v104Event?.state == snapshot(.rightStick(x: 0, y: 1), .rightTrigger(1)))
  }

  @Test
  func v103TouchReportCarriesTheTouchpadClick() throws {
    let driver = v103
    #expect(
      try driver.parseReport(Data([0x02, 0x01, 0, 0, 0]))?.state == snapshot(.press(.touchpadClick))
    )
    #expect(driver.capabilities.controls.contains(.touchpadClick))
  }

  @Test
  func otherReportsAreIgnored() throws {
    #expect(try v103.parseReport(Data([0x03] + [UInt8](repeating: 0, count: 32))) == nil)
    #expect(try v104.parseReport(Data([0x01] + [UInt8](repeating: 0, count: 17))) == nil)
    #expect(try v104.parseReport(Data([0x02, 0x01, 0, 0, 0])) == nil)
  }

  @Test
  func v103RumbleUsesTheSDLOutputReport() throws {
    let command = ControllerOutputCommand.setRumble(
      RumbleIntensities(leftMain: UnipolarValue(byte: 0x40), rightMain: UnipolarValue(byte: 0xC0)),
      duration: .held
    )
    #expect(
      try v103.encode(command).writes.hidOutputs.map(\.bytes) == [
        [0x01, 0x00, 0x40, 0x00, 0xC0, 0x00, 0x00]
      ]
    )
    #expect(
      try v103.encode(.stopRumble).writes.hidOutputs.map(\.bytes) == [
        [0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
      ]
    )
  }

  /// SDL disables V104 command reports on macOS because the write hangs for seconds.
  @Test
  func v104IsInputOnly() {
    #expect(v104.outputCapabilities == .none)
    #expect(v103.outputCapabilities == .dualMainRumble)
    #expect(throws: ControllerOutputError.self) { try v104.encode(.stopRumble) }
  }
}
