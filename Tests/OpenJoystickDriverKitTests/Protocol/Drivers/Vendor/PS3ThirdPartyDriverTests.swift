import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Reports in SDL's `HIDAPI_DriverPS3ThirdParty` layouts. The 19-byte-or-longer layout has digital
/// bits in byte 0, system bits in byte 1, the hat in the low nibble of byte 2, sticks at 3–6,
/// pressure at 7–16 and analog triggers at 17–18; the 18-byte layout moves the hat to the high
/// nibble of byte 1 and shifts sticks, pressure and triggers down by one.
private enum ThirdPartyReport {
  static func standard(_ bytes: [Int: UInt8] = [:], length: Int = 27) -> Data {
    var report = [UInt8](repeating: 0, count: length)
    report[2] = 0x0F
    for offset in 3...6 where offset < length { report[offset] = 0x80 }
    for (offset, value) in bytes { report[offset] = value }
    return Data(report)
  }

  static func compact(_ bytes: [Int: UInt8] = [:]) -> Data {
    var report = [UInt8](repeating: 0, count: 18)
    report[1] = 0xF0
    for offset in 2...5 { report[offset] = 0x80 }
    for (offset, value) in bytes { report[offset] = value }
    return Data(report)
  }
}

private let probeWithReportID = PhysicalHIDFeatureReadRequest(reportID: 0x03, length: 64)
private let probeWithoutReportID = PhysicalHIDFeatureReadRequest(reportID: 0x00, length: 64)

/// A third-party identity that SDL claims only after the feature probe.
private func probedDriver() -> PS3ThirdPartyDriver {
  PS3ThirdPartyDriver(identifier: DeviceIdentifier(vendorID: 0x0E8F, productID: 0x3075))
}

private func acceptedDriver() -> PS3ThirdPartyDriver {
  let driver = probedDriver()
  _ = driver.consumeFeatureReply(
    Data([0x03, 0x00, 0x26, 0, 0, 0, 0, 0]),
    request: probeWithReportID
  )
  return driver
}

private func gp100() -> PS3ThirdPartyDriver {
  PS3ThirdPartyDriver(identifier: DeviceIdentifier(vendorID: 0x2563, productID: 0x0575))
}

@Suite
struct PS3ThirdPartyDriverTests {

  // MARK: - Probe

  @Test
  func probeRequestsBothReportIDs() {
    #expect(probedDriver().startupFeatureReads() == [probeWithReportID, probeWithoutReportID])
  }

  @Test
  func probeAcceptsTheMarkerAtSDLByteTwo() {
    let withID = probedDriver()
    #expect(
      withID.consumeFeatureReply(Data([0x03, 0, 0x26, 0, 0, 0, 0, 0]), request: probeWithReportID)
    )
    #expect(withID.decodesRawReports)
    // IOKit omits the ID byte for report 0x00, so SDL's byte 2 arrives at byte 1.
    let withoutID = probedDriver()
    #expect(
      withoutID.consumeFeatureReply(
        Data([0, 0x26, 0, 0, 0, 0, 0, 0]),
        request: probeWithoutReportID
      )
    )
    #expect(withoutID.decodesRawReports)
  }

  @Test
  func probeRejectsOtherReplies() {
    let replies: [(Data, PhysicalHIDFeatureReadRequest)] = [
      (Data([0x03, 0, 0x26, 0, 0, 0, 0, 0, 0]), probeWithReportID),
      (Data([0x03, 0, 0x25, 0, 0, 0, 0, 0]), probeWithReportID),
      (Data([0x03, 0x26, 0, 0, 0, 0, 0, 0]), probeWithReportID),
      (Data([0, 0, 0x26, 0, 0, 0, 0, 0]), probeWithoutReportID),
      (
        Data([0, 0x26, 0, 0, 0, 0, 0, 0]), PhysicalHIDFeatureReadRequest(reportID: 0xF2, length: 64)
      ),
    ]
    for (reply, request) in replies {
      let driver = probedDriver()
      #expect(!driver.consumeFeatureReply(reply, request: request))
      #expect(!driver.decodesRawReports)
    }
  }

  @Test
  func descriptorMappingRunsUntilTheProbeAccepts() throws {
    let driver = probedDriver()
    let leftX = HIDElementValue(
      usagePage: 0x01,
      usage: 0x30,
      logicalMinimum: 0,
      logicalMaximum: 255,
      integerValue: 255
    )
    #expect(try driver.parseReport(ThirdPartyReport.standard([0: 0x02])) == nil)
    #expect(
      driver.parse(elementValue: leftX, receivedAt: MonotonicTimestamp(nanoseconds: 0)) != nil
    )
    _ = driver.consumeFeatureReply(
      Data([0x03, 0, 0x26, 0, 0, 0, 0, 0]),
      request: probeWithReportID
    )
    #expect(
      driver.parse(elementValue: leftX, receivedAt: MonotonicTimestamp(nanoseconds: 0)) == nil
    )
    #expect(
      try driver.parseReport(ThirdPartyReport.standard([0: 0x02])).contains(.press(.faceSouth))
    )
  }

  @Test
  func probeResultSurvivesAProtocolReset() {
    let driver = acceptedDriver()
    driver.resetProtocolState()
    #expect(driver.decodesRawReports)
  }

  @Test
  func chillStreamAndGP100SkipTheProbe() {
    for (vendor, product) in [(UInt16(0x046D), UInt16(0xCAD1)), (0x2563, 0x0575)] {
      let driver = PS3ThirdPartyDriver(
        identifier: DeviceIdentifier(vendorID: vendor, productID: product)
      )
      #expect(driver.decodesRawReports)
      #expect(driver.startupFeatureReads().isEmpty)
    }
  }

  // MARK: - 19-byte layout

  @Test
  func restingReportIsNeutral() throws {
    #expect(try acceptedDriver().parseReport(ThirdPartyReport.standard())?.state == .neutral)
  }

  @Test
  func mapsDigitalBitsOfByteZero() throws {
    let controls: [UInt8: ControlID] = [
      0x01: .faceWest, 0x02: .faceSouth, 0x04: .faceEast, 0x08: .faceNorth, 0x10: .leftShoulder,
      0x20: .rightShoulder,
    ]
    for (mask, control) in controls {
      let event = try acceptedDriver().parseReport(ThirdPartyReport.standard([0: mask]))
      #expect(event?.state == snapshot(.press(control)))
    }
  }

  @Test
  func digitalTriggerBitsReadAsFullyPulled() throws {
    let event = try acceptedDriver().parseReport(
      ThirdPartyReport.standard([0: 0xC0, 17: 0x10, 18: 0x20])
    )
    #expect(event?.state == snapshot(.leftTrigger(1), .rightTrigger(1)))
  }

  @Test
  func pressureBitSevenAlsoPresses() throws {
    let controls: [Int: ControlID] = [
      11: .faceNorth, 12: .faceEast, 13: .faceSouth, 14: .faceWest, 15: .leftShoulder,
      16: .rightShoulder,
    ]
    for (offset, control) in controls {
      let driver = acceptedDriver()
      #expect(try driver.parseReport(ThirdPartyReport.standard([offset: 0x7F]))?.state == .neutral)
      #expect(
        try driver.parseReport(ThirdPartyReport.standard([offset: 0x80]))?.state
          == snapshot(.press(control))
      )
    }
  }

  @Test
  func mapsSystemBitsOfByteOne() throws {
    let controls: [UInt8: ControlID] = [
      0x01: .view, 0x02: .menu, 0x04: .leftStickClick, 0x08: .rightStickClick, 0x10: .guide,
    ]
    for (mask, control) in controls {
      let event = try acceptedDriver().parseReport(ThirdPartyReport.standard([1: mask]))
      #expect(event?.state == snapshot(.press(control)))
    }
  }

  @Test
  func mapsTheHatNibble() throws {
    let directions: [HatDirection] = [
      .north, .northEast, .east, .southEast, .south, .southWest, .west, .northWest,
    ]
    let driver = acceptedDriver()
    _ = try driver.parseReport(ThirdPartyReport.standard())
    for (nibble, direction) in directions.enumerated() {
      let event = try driver.parseReport(ThirdPartyReport.standard([2: 0xF0 | UInt8(nibble)]))
      #expect(event?.state == snapshot(.hat(direction)))
    }
    #expect(try driver.parseReport(ThirdPartyReport.standard([2: 0x08]))?.state == .neutral)
  }

  @Test
  func centeredHatFallsBackToDpadPressure() throws {
    let driver = acceptedDriver()
    // Pressure bytes 7–10 are right, left, up, down.
    #expect(try driver.parseReport(ThirdPartyReport.standard([9: 0xFF])).contains(.hat(.north)))
    #expect(
      try driver.parseReport(ThirdPartyReport.standard([10: 0xFF, 8: 0xFF])).contains(
        .hat(.southWest)
      )
    )
    #expect(
      try driver.parseReport(ThirdPartyReport.standard([9: 0xFF, 10: 0xFF]))?.state == .neutral
    )
  }

  @Test
  func hatNibbleOfZeroIsIgnoredUntilTheHatMoves() throws {
    let driver = acceptedDriver()
    // SDL only decodes the hat when it changes from zero, so a constant 0 never reads as north.
    #expect(try driver.parseReport(ThirdPartyReport.standard([2: 0x00]))?.state == .neutral)
    #expect(try driver.parseReport(ThirdPartyReport.standard([2: 0x0F]))?.state == .neutral)
    #expect(try driver.parseReport(ThirdPartyReport.standard([2: 0x00])).contains(.hat(.north)))
    driver.resetProtocolState()
    #expect(try driver.parseReport(ThirdPartyReport.standard([2: 0x00]))?.state == .neutral)
  }

  @Test
  func mapsSticksAndAnalogTriggers() throws {
    let event = try acceptedDriver().parseReport(
      ThirdPartyReport.standard([3: 0xFF, 4: 0x00, 5: 0x00, 6: 0xFF, 17: 0xFF, 18: 0x80])
    )
    #expect(
      event?.state
        == snapshot(
          .leftStick(x: 1, y: -1),
          .rightStick(x: -1, y: 1),
          .leftTrigger(1),
          .rightTrigger(Float(0x80) / 255)
        )
    )
  }

  @Test
  func shortReportIsIgnoredAndKeepsState() throws {
    let driver = acceptedDriver()
    #expect(
      try driver.parseReport(ThirdPartyReport.standard([0: 0x02])).contains(.press(.faceSouth))
    )
    #expect(try driver.parseReport(ThirdPartyReport.standard(length: 17)) == nil)
    #expect(
      try driver.parseReport(ThirdPartyReport.standard([0: 0x02])).contains(.press(.faceSouth))
    )
  }

  @Test
  func axisBytesSpanTheFullRange() {
    #expect(PS3ThirdPartyDriver.axis(0x00) == -1)
    #expect(PS3ThirdPartyDriver.axis(0x80) == 0)
    #expect(PS3ThirdPartyDriver.axis(0xFF) == 1)
  }

  // MARK: - 18-byte layout

  @Test
  func compactReportMovesHatAndShiftsBytes() throws {
    let driver = acceptedDriver()
    #expect(try driver.parseReport(ThirdPartyReport.compact())?.state == .neutral)
    let event = try driver.parseReport(
      ThirdPartyReport.compact([0: 0x04, 1: 0x21, 2: 0xFF, 5: 0x00, 12: 0x80, 16: 0xFF])
    )
    #expect(
      event?.state
        == snapshot(
          .press(.faceEast),
          .press(.view),
          .press(.faceSouth),
          .hat(.east),
          .leftStick(x: 1, y: 0),
          .rightStick(x: 0, y: -1),
          .leftTrigger(1)
        )
    )
  }

  @Test
  func compactReportHasNoGuideOrDigitalTriggers() throws {
    let event = try acceptedDriver().parseReport(
      ThirdPartyReport.compact([0: 0xC0, 1: 0xF0 | 0x10])
    )
    #expect(event?.state == .neutral)
  }

  // MARK: - Device quirks

  @Test
  func cyborgV3ReadsTheHatFromAnyDpadPressure() throws {
    let driver = PS3ThirdPartyDriver(
      identifier: DeviceIdentifier(vendorID: 0x06A3, productID: 0xF622)
    )
    _ = driver.consumeFeatureReply(
      Data([0x03, 0, 0x26, 0, 0, 0, 0, 0]),
      request: probeWithReportID
    )
    #expect(try driver.parseReport(ThirdPartyReport.standard([2: 0x02]))?.state == .neutral)
    #expect(try driver.parseReport(ThirdPartyReport.standard([7: 0x01])).contains(.hat(.east)))
  }

  /// Button map an Ant Esports GP100 owner recorded with a raw HID probe (issue #38).
  @Test
  func gp100MapsPressureBytesToButtons() throws {
    let controls: [Int: ControlID] = [
      11: .faceNorth, 12: .faceEast, 13: .faceSouth, 14: .faceWest, 15: .leftShoulder,
      16: .rightShoulder,
    ]
    for (offset, control) in controls {
      let driver = gp100()
      #expect(
        try driver.parseReport(ThirdPartyReport.standard([offset: 0xFF]))?.state
          == snapshot(.press(control))
      )
      #expect(try driver.parseReport(ThirdPartyReport.standard()).contains(.release(control)))
    }
  }

  @Test
  func gp100IgnoresByteZeroAndTheHatNibble() throws {
    let driver = gp100()
    // PR #42 reads byte 0 as a report ID and byte 2 as unused; neither is verified as input.
    #expect(
      try driver.parseReport(ThirdPartyReport.standard([0: 0xFF, 2: 0x01]))?.state == .neutral
    )
    #expect(try driver.parseReport(ThirdPartyReport.standard([2: 0x00]))?.state == .neutral)
    #expect(try driver.parseReport(ThirdPartyReport.standard([9: 0xFF])).contains(.hat(.north)))
  }

  // MARK: - Output

  /// The report an owner's hidapi script drove on hardware; weak motor in byte 2, strong in 3.
  @Test
  func gp100RumbleUsesTheHardwareVerifiedReport() throws {
    let command = ControllerOutputCommand.setRumble(
      RumbleIntensities(leftMain: UnipolarValue(byte: 0x40), rightMain: UnipolarValue(byte: 0xC0)),
      duration: .held
    )
    let plan = try gp100().encode(command)
    #expect(plan.writes.hidOutputs.map(\.reportID) == [0x02])
    #expect(plan.writes.hidOutputs.map(\.bytes) == [[0x02, 0x00, 0xC0, 0x40, 0, 0, 0, 0]])
    #expect(
      try gp100().encode(.stopRumble).writes.hidOutputs.map(\.bytes) == [
        [0x02, 0x00, 0x00, 0x00, 0, 0, 0, 0]
      ]
    )
    #expect(gp100().outputCapabilities == .dualMainRumble)
  }

  /// SDL sends third-party pads no output, because some then rumble without stopping.
  @Test
  func otherThirdPartyPadsAreInputOnly() {
    #expect(acceptedDriver().outputCapabilities == .none)
    #expect(throws: ControllerOutputError.self) { try acceptedDriver().encode(.stopRumble) }
  }

  @Test
  func catalogBindsTheGP100ToTheThirdPartyFamily() {
    let record = DeviceCatalog().record(for: DeviceIdentifier(vendorID: 0x2563, productID: 0x0575))
    #expect(record?.physicalProtocolID == .vendorPS3ThirdParty)
  }
}
