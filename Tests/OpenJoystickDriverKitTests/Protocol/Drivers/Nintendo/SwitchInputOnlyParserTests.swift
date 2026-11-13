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
struct SwitchInputOnlyParserTests {
  static let family = PhysicalProtocolID.nintendoSwitchInputOnly
  static let model = ControllerModelID(vendorID: 0x0F0D, productID: 0x00C1)

  @Test
  func inputOnlyRowsBindNintendoSwitchInputOnlyAndBuildItsDriver() throws {
    let models = [(0x0E6F, 0x0180), (0x0F0D, 0x0092)].map {
      ControllerModelID(vendorID: $0.0, productID: $0.1)
    }
    for model in models {
      let record = try #require(ProtocolDriverRegistry().record(for: model), "\(model)")
      #expect(record.physicalProtocolID == .nintendoSwitchInputOnly, "\(model)")
      #expect(try catalogParser(model) is ReportLayoutDriver, "\(model)")
    }
  }

  @Test
  func restingReportIsNeutral() throws {
    #expect(try switchInputOnlyDriver().parseReport(InputOnlyReport.with())?.state == .neutral)
  }

  @Test
  func mapsButtonBitsByNintendoPosition() throws {
    let controls: [(Int, UInt8, Control)] = [
      (0, 0x01, .west), (0, 0x02, .south), (0, 0x04, .east), (0, 0x08, .north),
      (0, 0x10, .leftShoulder), (0, 0x20, .rightShoulder), (0, 0x40, .leftTrigger),
      (0, 0x80, .rightTrigger), (1, 0x01, .back), (1, 0x02, .start),
      (1, 0x04, .leftStickClick), (1, 0x08, .rightStickClick), (1, 0x10, .guide),
      (1, 0x20, .capture),
    ]
    for (offset, mask, control) in controls {
      let driver = switchInputOnlyDriver()
      #expect(
        try driver.parseReport(InputOnlyReport.with([offset: mask])).contains(.press(control)),
        "\(control)"
      )
      #expect(try driver.parseReport(InputOnlyReport.with()).contains(.release(control)))
    }
  }

  @Test
  func decodesHatClockwiseFromUpAndTreatsOtherValuesAsNeutral() throws {
    let directions: [HatDirection] = [
      .north, .northEast, .east, .southEast, .south, .southWest, .west, .northWest,
    ]
    for (value, direction) in directions.enumerated() {
      let event = try switchInputOnlyDriver().parseReport(InputOnlyReport.with([2: UInt8(value)]))
      #expect(event?.state.hat == direction)
    }
    for value: UInt8 in [0x08, 0x0F, 0xFF] {
      let event = try switchInputOnlyDriver().parseReport(InputOnlyReport.with([2: value]))
      #expect(event?.state.hat == .neutral)
    }
  }

  @Test
  func decodesSticksWithUpAndLeftLow() throws {
    let event = try #require(
      try switchInputOnlyDriver().parseReport(
        InputOnlyReport.with([3: 0x00, 4: 0xFF, 5: 0xFF, 6: 0x00])
      )
    )
    #expect(event.state.leftStick == StickPosition(x: -1, y: 1))
    #expect(event.state.rightStick == StickPosition(x: 1, y: -1))
  }

  @Test
  func ignoresShortReports() throws {
    #expect(try switchInputOnlyDriver().parseReport(Data([0, 0, 8, 0x80, 0x80, 0x80])) == nil)
  }
}
