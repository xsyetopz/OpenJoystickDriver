import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Reports in the SDL `SwitchInputOnlyControllerStatePacket_t` layout: two button bytes, a hat
/// byte, then four stick bytes centered on 128, followed by one vendor byte.
private enum InputOnlyReport {
  static func with(_ bytes: [Int: UInt8] = [:]) -> Data {
    var report: [UInt8] = [0, 0, 0x08, 0x80, 0x80, 0x80, 0x80, 0]
    for (offset, value) in bytes { report[offset] = value }
    return Data(report)
  }
}

@Suite
struct SwitchInputOnlyDriverTests {

  @Test
  func restingReportIsNeutral() throws {
    #expect(try SwitchInputOnlyDriver().parseReport(InputOnlyReport.with())?.state == .neutral)
  }

  @Test
  func mapsButtonBitsByNintendoPosition() throws {
    let controls: [(Int, UInt8, ControlID)] = [
      (0, 0x01, .faceWest), (0, 0x02, .faceSouth), (0, 0x04, .faceEast), (0, 0x08, .faceNorth),
      (0, 0x10, .leftShoulder), (0, 0x20, .rightShoulder), (0, 0x40, .leftTriggerButton),
      (0, 0x80, .rightTriggerButton), (1, 0x01, .view), (1, 0x02, .menu),
      (1, 0x04, .leftStickClick), (1, 0x08, .rightStickClick), (1, 0x10, .guide),
      (1, 0x20, .capture),
    ]
    for (offset, mask, control) in controls {
      let driver = SwitchInputOnlyDriver()
      #expect(
        try driver.parseReport(InputOnlyReport.with([offset: mask])).contains(.press(control)),
        "\(control)"
      )
      #expect(try driver.parseReport(InputOnlyReport.with()).contains(.release(control)))
    }
  }

  @Test
  func decodesTheHatClockwiseFromUpAndTreatsOtherValuesAsNeutral() throws {
    let directions: [HatDirection] = [
      .north, .northEast, .east, .southEast, .south, .southWest, .west, .northWest,
    ]
    for (value, direction) in directions.enumerated() {
      let event = try SwitchInputOnlyDriver().parseReport(InputOnlyReport.with([2: UInt8(value)]))
      #expect(event?.state.hat == direction)
    }
    for value: UInt8 in [0x08, 0x0F, 0xFF] {
      let event = try SwitchInputOnlyDriver().parseReport(InputOnlyReport.with([2: value]))
      #expect(event?.state.hat == .neutral)
    }
  }

  @Test
  func decodesSticksWithUpAndLeftLow() throws {
    let event = try #require(
      try SwitchInputOnlyDriver().parseReport(
        InputOnlyReport.with([3: 0x00, 4: 0xFF, 5: 0xFF, 6: 0x00])
      )
    )
    #expect(event.state.leftStick == StickPosition(x: -1, yDown: 1))
    #expect(event.state.rightStick == StickPosition(x: 1, yDown: -1))
  }

  @Test
  func ignoresShortReports() throws {
    #expect(try SwitchInputOnlyDriver().parseReport(Data([0, 0, 8, 0x80, 0x80, 0x80])) == nil)
  }
}
