import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Reports built from the byte map an Ant Esports GP100 (`2563:0575`, PS3/PC mode) owner recorded
/// with a raw HID probe (issue #38), matching SDL's `PS3ThirdParty` layout: sticks at 3–6,
/// pressure bytes at 7–16, analog triggers at 17–18.
private enum ShanwanReport {
  static let length = 27

  static func with(_ bytes: [Int: UInt8] = [:], length: Int = length) -> Data {
    var report = [UInt8](repeating: 0, count: length)
    for offset in 3...6 where offset < length { report[offset] = 0x80 }
    for (offset, value) in bytes { report[offset] = value }
    return Data(report)
  }
}

@Suite
struct ShanwanDriverTests {

  @Test
  func restingReportIsNeutral() throws {
    #expect(try ShanwanDriver().parseReport(ShanwanReport.with())?.state == .neutral)
  }

  @Test
  func mapsPressureBytesToFaceButtonsAndBumpers() throws {
    let controls: [Int: ControlID] = [
      11: .faceNorth, 12: .faceEast, 13: .faceSouth, 14: .faceWest, 15: .leftShoulder,
      16: .rightShoulder,
    ]
    for (offset, control) in controls {
      let parser = ShanwanDriver()
      let event = try parser.parseReport(ShanwanReport.with([offset: 0xFF]))
      #expect(event?.state == snapshot(.press(control)))
      #expect(try parser.parseReport(ShanwanReport.with()).contains(.release(control)))
    }
  }

  @Test
  func pressureBytesCountAsPressedFromBitSeven() throws {
    for (offset, control) in [(13, ControlID.faceSouth), (15, .leftShoulder)] {
      let parser = ShanwanDriver()
      #expect(try parser.parseReport(ShanwanReport.with([offset: 0x40]))?.state == .neutral)
      #expect(try parser.parseReport(ShanwanReport.with([offset: 0x80])).contains(.press(control)))
      let below = try parser.parseReport(ShanwanReport.with([offset: 0x7F]))
      #expect(below.contains(.release(control)))
      #expect(try parser.parseReport(ShanwanReport.with([offset: 0xFF])).contains(.press(control)))
    }
    #expect(try ShanwanDriver().parseReport(ShanwanReport.with([9: 0x40]))?.state == .neutral)
    #expect(try ShanwanDriver().parseReport(ShanwanReport.with([9: 0x80])).contains(.hat(.north)))
    #expect(try ShanwanDriver().parseReport(ShanwanReport.with([9: 0xFF])).contains(.hat(.north)))
  }

  @Test
  func mapsSystemBitsOfByteOne() throws {
    let controls: [UInt8: ControlID] = [
      0x01: .view, 0x02: .menu, 0x04: .leftStickClick, 0x08: .rightStickClick, 0x10: .guide,
    ]
    for (mask, control) in controls {
      let event = try ShanwanDriver().parseReport(ShanwanReport.with([1: mask]))
      #expect(event?.state == snapshot(.press(control)))
    }
  }

  @Test
  func combinesDpadPressureBytesIntoHat() throws {
    let parser = ShanwanDriver()
    // Offsets 7–10 are right, left, up, down.
    #expect(try parser.parseReport(ShanwanReport.with([9: 0xFF])).contains(.hat(.north)))
    #expect(
      try parser.parseReport(ShanwanReport.with([9: 0xFF, 7: 0xFF])).contains(.hat(.northEast))
    )
    #expect(
      try parser.parseReport(ShanwanReport.with([10: 0xFF, 8: 0xFF])).contains(.hat(.southWest))
    )
    #expect(
      try parser.parseReport(ShanwanReport.with([9: 0xFF, 10: 0xFF])).contains(.hat(.neutral))
    )
  }

  @Test
  func mapsSticksAndAnalogTriggers() throws {
    let event = try ShanwanDriver().parseReport(
      ShanwanReport.with([3: 0xFF, 4: 0x00, 5: 0x00, 6: 0xFF, 17: 0xFF, 18: 0x80])
    )
    #expect(event.contains(.leftStick(x: 1, y: -1)))
    #expect(event.contains(.rightStick(x: -1, y: 1)))
    #expect(event.contains(.leftTrigger(1)))
    #expect(event.contains(.rightTrigger(Float(0x80) / 255)))
  }

  @Test
  func shortReportIsIgnoredAndKeepsState() throws {
    let parser = ShanwanDriver()
    #expect(try parser.parseReport(ShanwanReport.with([13: 0xFF])).contains(.press(.faceSouth)))
    #expect(try parser.parseReport(ShanwanReport.with(length: 18)) == nil)
    #expect(try parser.parseReport(ShanwanReport.with([13: 0xFF])).contains(.press(.faceSouth)))
  }

  @Test
  func axisBytesSpanTheFullRange() {
    #expect(ShanwanDriver.axis(0x00) == -1)
    #expect(ShanwanDriver.axis(0x80) == 0)
    #expect(ShanwanDriver.axis(0xFF) == 1)
  }

  @Test
  func catalogBindsTheGP100ToTheShanwanFamily() {
    let record = DeviceCatalog().record(for: DeviceIdentifier(vendorID: 0x2563, productID: 0x0575))
    #expect(record?.physicalProtocolID == .vendorShanwan)
  }
}
