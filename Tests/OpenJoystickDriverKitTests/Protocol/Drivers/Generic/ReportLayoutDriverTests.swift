import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// A 27-byte report with every control at rest in the GP100's layout: sticks centered at 0x80
/// and the unused hat nibble of byte 2 centered at 0x0F.
private func gp100Report(_ bytes: [Int: UInt8] = [:]) -> Data {
  var report = [UInt8](repeating: 0, count: 27)
  report[2] = 0x0F
  for offset in 3...6 { report[offset] = 0x80 }
  for (offset, value) in bytes { report[offset] = value }
  return Data(report)
}

/// An 18-byte ChillStream report at rest: hat nibble centered and sticks at 0x80.
private func chillStreamReport(_ bytes: [Int: UInt8] = [:]) -> Data {
  var report = [UInt8](repeating: 0, count: 18)
  report[1] = 0xF0
  for offset in 2...5 { report[offset] = 0x80 }
  for (offset, value) in bytes { report[offset] = value }
  return Data(report)
}

private let gp100Identifier = DeviceIdentifier(vendorID: 0x2563, productID: 0x0575)
private let chillStreamIdentifier = DeviceIdentifier(vendorID: 0x046D, productID: 0xCAD1)

/// The driver the registry builds from a bundled record.
private func catalogDriver(_ identifier: DeviceIdentifier) throws -> ReportLayoutDriver {
  try #require(try catalogParser(identifier) as? ReportLayoutDriver)
}

/// A layout decoded from an `input` section.
func inputLayout(_ json: String) throws -> ControllerInputLayout {
  try JSONDecoder().decode(ControllerRecordDocument.InputLayout.self, from: Data(json.utf8)).layout
}

@Suite
struct ReportLayoutDriverTests {

  // MARK: - Catalog rows

  @Test(arguments: [gp100Identifier, chillStreamIdentifier])
  func probeFreePadsBindTheReportLayoutFamily(identifier: DeviceIdentifier) throws {
    let record = try #require(DeviceCatalog().record(for: identifier))
    #expect(record.physicalProtocolID == .hidReportLayout)
    #expect(record.inputLayout != nil)
    let driver = try catalogDriver(identifier)
    #expect(driver.startupFeatureReads().isEmpty)
  }

  // MARK: - GP100

  /// Button map an Ant Esports GP100 owner recorded with a raw HID probe (issue #38).
  @Test
  func gp100MapsPressureBytesToButtons() throws {
    let controls: [Int: ControlID] = [
      11: .faceNorth, 12: .faceEast, 13: .faceSouth, 14: .faceWest, 15: .leftShoulder,
      16: .rightShoulder,
    ]
    for (offset, control) in controls {
      let driver = try catalogDriver(gp100Identifier)
      #expect(
        try driver.parseReport(gp100Report([offset: 0xFF]))?.state == snapshot(.press(control))
      )
      #expect(try driver.parseReport(gp100Report()).contains(.release(control)))
    }
  }

  @Test
  func gp100IgnoresByteZeroAndTheHatNibble() throws {
    let driver = try catalogDriver(gp100Identifier)
    // PR #42 reads byte 0 as a report ID and byte 2 as unused; neither is verified as input.
    #expect(try driver.parseReport(gp100Report([0: 0xFF, 2: 0x01]))?.state == .neutral)
    #expect(try driver.parseReport(gp100Report([2: 0x00]))?.state == .neutral)
    #expect(try driver.parseReport(gp100Report([9: 0xFF])).contains(.hat(.north)))
  }

  @Test
  func gp100IgnoresShortReports() throws {
    let driver = try catalogDriver(gp100Identifier)
    #expect(try driver.parseReport(Data(gp100Report([11: 0xFF]).prefix(18))) == nil)
  }

  /// The report an owner's hidapi script drove on hardware; weak motor in byte 2, strong in 3.
  /// The GP100 record's rumble template encodes it.
  @Test
  func gp100RumbleUsesTheHardwareVerifiedReport() throws {
    let command = ControllerOutputCommand.setRumble(
      RumbleIntensities(leftMain: UnipolarValue(byte: 0x40), rightMain: UnipolarValue(byte: 0xC0)),
      duration: .held
    )
    let driver = try catalogDriver(gp100Identifier)
    let plan = try driver.encode(command)
    #expect(plan.writes.hidOutputs.map(\.reportID) == [0x02])
    #expect(plan.writes.hidOutputs.map(\.bytes) == [[0x02, 0x00, 0xC0, 0x40, 0, 0, 0, 0]])
    #expect(
      try driver.encode(.stopRumble).writes.hidOutputs.map(\.bytes) == [
        [0x02, 0x00, 0x00, 0x00, 0, 0, 0, 0]
      ]
    )
    #expect(driver.outputCapabilities == .dualMainRumble)
  }

  // MARK: - ChillStream

  @Test
  func chillStreamMovesHatAndShiftsBytes() throws {
    let driver = try catalogDriver(chillStreamIdentifier)
    #expect(try driver.parseReport(chillStreamReport())?.state == .neutral)
    let event = try driver.parseReport(
      chillStreamReport([0: 0x04, 1: 0x21, 2: 0xFF, 5: 0x00, 12: 0x80, 16: 0xFF])
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
  func chillStreamHasNoGuideOrDigitalTriggers() throws {
    let event = try catalogDriver(chillStreamIdentifier).parseReport(
      chillStreamReport([0: 0xC0, 1: 0xF0 | 0x10])
    )
    #expect(event?.state == .neutral)
  }

  @Test
  func chillStreamHatOfZeroIsIgnoredUntilTheHatMoves() throws {
    let driver = try catalogDriver(chillStreamIdentifier)
    // SDL only decodes the hat when it changes from zero, so a constant 0 never reads as north.
    #expect(try driver.parseReport(chillStreamReport([1: 0x00]))?.state == .neutral)
    #expect(try driver.parseReport(chillStreamReport([1: 0xF0]))?.state == .neutral)
    #expect(try driver.parseReport(chillStreamReport([1: 0x00])).contains(.hat(.north)))
    driver.resetProtocolState()
    #expect(try driver.parseReport(chillStreamReport([1: 0x00]))?.state == .neutral)
  }

  @Test
  func chillStreamCenteredHatFallsBackToDpadPressure() throws {
    let driver = try catalogDriver(chillStreamIdentifier)
    // Pressure bytes 6–9 are right, left, up, down.
    #expect(try driver.parseReport(chillStreamReport([8: 0xFF])).contains(.hat(.north)))
    #expect(
      try driver.parseReport(chillStreamReport([9: 0xFF, 7: 0xFF])).contains(.hat(.southWest))
    )
    #expect(try driver.parseReport(chillStreamReport([8: 0xFF, 9: 0xFF]))?.state == .neutral)
  }

  @Test
  func chillStreamFaceButtonsReadFromBitsOrPressure() throws {
    let driver = try catalogDriver(chillStreamIdentifier)
    #expect(
      try driver.parseReport(chillStreamReport([0: 0x08]))?.state == snapshot(.press(.faceNorth))
    )
    #expect(
      try driver.parseReport(chillStreamReport([10: 0x80]))?.state == snapshot(.press(.faceNorth))
    )
    #expect(try driver.parseReport(chillStreamReport()).contains(.release(.faceNorth)))
  }

  // MARK: - Layout fields

  @Test
  func reportWithAnotherIDIsIgnored() throws {
    let driver = ReportLayoutDriver(
      layout: try inputLayout(
        #"{"report": {"id": 5, "length": 2}, "#
          + #""buttons": [{"control": "face-south", "byte": 1, "mask": 1}]}"#
      )
    )
    #expect(try driver.parseReport(Data([6, 1])) == nil)
    #expect(try driver.parseReport(Data([5, 1]))?.state == snapshot(.press(.faceSouth)))
    #expect(driver.outputCapabilities == .none)
    #expect(throws: ControllerOutputError.self) { try driver.encode(.stopRumble) }
  }

  @Test
  func axesScaleTheirRangeAroundItsMiddle() throws {
    let layout = try inputLayout(
      """
      {"report": {"length": 4}, "axes": [
        {"control": "left-stick-x", "byte": 0, "bits": 16, "signed": true},
        {"control": "left-stick-y", "byte": 2, "inverted": true},
        {"control": "right-stick-x", "byte": 3, "min": 0, "max": 200}
      ]}
      """
    )
    let signed = layout.axes[0]
    #expect(signed.value(in: [0xFF, 0x7F, 0, 0]) == 1)
    #expect(signed.value(in: [0x00, 0x80, 0, 0]) == -1)
    #expect(signed.value(in: [0x00, 0x00, 0, 0]) == 0)
    let inverted = layout.axes[1]
    #expect(inverted.value(in: [0, 0, 0xFF, 0]) == -1)
    #expect(inverted.value(in: [0, 0, 0x00, 0]) == 1)
    let custom = layout.axes[2]
    #expect(custom.value(in: [0, 0, 0, 200]) == 1)
    #expect(custom.value(in: [0, 0, 0, 0]) == -1)
    #expect(custom.value(in: [0, 0, 0, 255]) == 1)
  }

  @Test
  func triggerButtonReadsAsFullyPulled() throws {
    let layout = try inputLayout(
      #"{"report": {"length": 2}, "leftTrigger": {"byte": 0, "button": {"byte": 1, "mask": 4}}}"#
    )
    let trigger = try #require(layout.leftTrigger)
    #expect(trigger.value(in: [0x00, 0x04]) == UnipolarValue(normalized: 1))
    #expect(trigger.value(in: [0xFF, 0x00]) == UnipolarValue(normalized: 1))
    #expect(trigger.value(in: [0x00, 0x00]) == UnipolarValue(normalized: 0))
    #expect(layout.controls == [.leftTrigger])
  }
}
