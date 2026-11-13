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

private let gp100Model = ControllerModelID(vendorID: 0x2563, productID: 0x0575)
private let chillStreamModel = ControllerModelID(vendorID: 0x046D, productID: 0xCAD1)

/// The driver the registry builds from a bundled record.
private func catalogDriver(_ model: ControllerModelID) throws -> ReportLayoutDriver {
  try #require(try catalogParser(model) as? ReportLayoutDriver)
}

/// A layout decoded from an `input` section.
func inputLayout(_ json: String) throws -> ControllerInputLayout {
  try JSONDecoder().decode(ControllerRecordDocument.InputLayout.self, from: Data(json.utf8)).layout
}

/// A driver for the one layout.
func layoutDriver(_ layout: ControllerInputLayout) throws -> ReportLayoutDriver {
  ReportLayoutDriver(layouts: try ControllerInputLayouts(layouts: [layout]))
}

@Suite
struct ReportLayoutDriverTests {
  static let family = PhysicalProtocolID.hidReportLayout
  static let model = ControllerModelID(vendorID: 0x2563, productID: 0x0575)

  // MARK: - Catalog rows

  @Test(arguments: [gp100Model, chillStreamModel])
  func probeFreePadsBindTheReportLayoutFamily(model: ControllerModelID) throws {
    let record = try #require(DeviceCatalog().record(for: model))
    #expect(record.physicalProtocolID == .hidReportLayout)
    #expect(record.inputLayouts != nil)
    let driver = try catalogDriver(model)
    #expect(driver.startupFeatureReads().isEmpty)
  }

  // MARK: - GP100

  /// Button map an Ant Esports GP100 owner recorded with a raw HID probe (issue #38).
  @Test
  func gp100MapsPressureBytesToButtons() throws {
    let controls: [Int: Control] = [
      11: .north, 12: .east, 13: .south, 14: .west, 15: .leftShoulder,
      16: .rightShoulder,
    ]
    for (offset, control) in controls {
      let driver = try catalogDriver(gp100Model)
      #expect(
        try driver.parseReport(gp100Report([offset: 0xFF]))?.state == snapshot(.press(control))
      )
      #expect(try driver.parseReport(gp100Report()).contains(.release(control)))
    }
  }

  /// The same issue #38 mapping file: byte 1 bits 0 to 3, the four pressure D-pad bytes, the
  /// trigger bytes and the stick X bytes.
  @Test
  func gp100MapsMenuBitsDpadTriggersAndStickX() throws {
    let bits: [UInt8: Control] = [
      0x01: .back, 0x02: .start, 0x04: .leftStickClick, 0x08: .rightStickClick,
    ]
    for (mask, control) in bits {
      let driver = try catalogDriver(gp100Model)
      #expect(
        try driver.parseReport(gp100Report([1: mask]))?.state == snapshot(.press(control))
      )
    }
    let hats: [Int: HatDirection] = [7: .east, 8: .west, 9: .north, 10: .south]
    for (offset, direction) in hats {
      let driver = try catalogDriver(gp100Model)
      #expect(
        try driver.parseReport(gp100Report([offset: 0xFF]))?.state == snapshot(.hat(direction))
      )
    }
    #expect(
      try catalogDriver(gp100Model).parseReport(gp100Report([17: 0xFF]))?.state
        == snapshot(.leftTrigger(1))
    )
    #expect(
      try catalogDriver(gp100Model).parseReport(gp100Report([18: 0xFF]))?.state
        == snapshot(.rightTrigger(1))
    )
    #expect(
      try catalogDriver(gp100Model).parseReport(gp100Report([3: 0xFF]))?.state
        == snapshot(.leftStick(x: 1, y: 0))
    )
    #expect(
      try catalogDriver(gp100Model).parseReport(gp100Report([5: 0xFF]))?.state
        == snapshot(.rightStick(x: 1, y: 0))
    )
  }

  @Test
  func gp100IgnoresByteZeroAndTheHatNibble() throws {
    let driver = try catalogDriver(gp100Model)
    // PR #42 reads byte 0 as a report ID and byte 2 as unused; neither is verified as input.
    #expect(try driver.parseReport(gp100Report([0: 0xFF, 2: 0x01]))?.state == .neutral)
    #expect(try driver.parseReport(gp100Report([2: 0x00]))?.state == .neutral)
    #expect(try driver.parseReport(gp100Report([9: 0xFF])).contains(.hat(.north)))
  }

  @Test
  func gp100IgnoresShortReports() throws {
    let driver = try catalogDriver(gp100Model)
    #expect(try driver.parseReport(Data(gp100Report([11: 0xFF]).prefix(18))) == nil)
  }

  /// The report an owner's hidapi script drove on hardware; weak motor in byte 2, strong in 3.
  ///
  /// The GP100 record's rumble template encodes it.
  @Test
  func gp100RumbleUsesTheHardwareVerifiedReport() throws {
    let command = ControllerOutputCommand.setRumble(
      RumbleIntensities(
        lowFrequency: UnipolarValue(byte: 0x40),
        highFrequency: UnipolarValue(byte: 0xC0)
      ),
      duration: .held
    )
    let driver = try catalogDriver(gp100Model)
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
    let driver = try catalogDriver(chillStreamModel)
    #expect(try driver.parseReport(chillStreamReport())?.state == .neutral)
    let event = try driver.parseReport(
      chillStreamReport([0: 0x04, 1: 0x21, 2: 0xFF, 5: 0x00, 12: 0x80, 16: 0xFF])
    )
    #expect(
      event?.state
        == snapshot(
          .press(.east),
          .press(.back),
          .press(.south),
          .hat(.east),
          .leftStick(x: 1, y: 0),
          .rightStick(x: 0, y: -1),
          .leftTrigger(1)
        )
    )
  }

  @Test
  func chillStreamHasNoGuideOrDigitalTriggers() throws {
    let event = try catalogDriver(chillStreamModel).parseReport(
      chillStreamReport([0: 0xC0, 1: 0xF0 | 0x10])
    )
    #expect(event?.state == .neutral)
  }

  @Test
  func chillStreamHatOfZeroIsIgnoredUntilTheHatMoves() throws {
    let driver = try catalogDriver(chillStreamModel)
    // SDL only decodes the hat when it changes from zero, so a constant 0 never reads as north.
    #expect(try driver.parseReport(chillStreamReport([1: 0x00]))?.state == .neutral)
    #expect(try driver.parseReport(chillStreamReport([1: 0xF0]))?.state == .neutral)
    #expect(try driver.parseReport(chillStreamReport([1: 0x00])).contains(.hat(.north)))
    driver.resetProtocolState()
    #expect(try driver.parseReport(chillStreamReport([1: 0x00]))?.state == .neutral)
  }

  @Test
  func chillStreamCenteredHatFallsBackToDpadPressure() throws {
    let driver = try catalogDriver(chillStreamModel)
    // Pressure bytes 6–9 are right, left, up, down.
    #expect(try driver.parseReport(chillStreamReport([8: 0xFF])).contains(.hat(.north)))
    #expect(
      try driver.parseReport(chillStreamReport([9: 0xFF, 7: 0xFF])).contains(.hat(.southWest))
    )
    #expect(try driver.parseReport(chillStreamReport([8: 0xFF, 9: 0xFF]))?.state == .neutral)
  }

  @Test
  func chillStreamFaceButtonsReadFromBitsOrPressure() throws {
    let driver = try catalogDriver(chillStreamModel)
    #expect(
      try driver.parseReport(chillStreamReport([0: 0x08]))?.state == snapshot(.press(.north))
    )
    #expect(
      try driver.parseReport(chillStreamReport([10: 0x80]))?.state == snapshot(.press(.north))
    )
    #expect(try driver.parseReport(chillStreamReport()).contains(.release(.north)))
  }

  // MARK: - Layout fields

  @Test
  func reportWithAnotherIDIsIgnored() throws {
    let driver = try layoutDriver(
      try inputLayout(
        #"{"report": {"id": 5, "length": {"atLeast": 2}}, "#
          + #""buttons": [{"control": "South", "bitOffset": 8, "bitSize": 1}]}"#
      )
    )
    #expect(try driver.parseReport(Data([6, 1])) == nil)
    #expect(try driver.parseReport(Data([5, 1]))?.state == snapshot(.press(.south)))
    #expect(driver.outputCapabilities == .none)
    #expect(throws: ControllerOutputError.self) { try driver.encode(.stopRumble) }
  }

  @Test
  func axesScaleTheirRangeAroundItsMiddle() throws {
    let layout = try inputLayout(
      """
      {"report": {"length": {"atLeast": 4}}, "axes": [
        {"control": "LeftStickX", "bitOffset": 0, "bitSize": 16, "signed": true},
        {"control": "LeftStickY", "bitOffset": 16, "bitSize": 8, "inverted": true},
        {"control": "RightStickX", "bitOffset": 24, "bitSize": 8, "min": 0, "max": 200}
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
      #"{"report": {"length": {"atLeast": 2}}, "leftTrigger": {"bitOffset": 0, "bitSize": 8, "#
        + #""button": {"bitOffset": 10, "bitSize": 1}}}"#
    )
    let trigger = try #require(layout.leftTrigger)
    #expect(trigger.value(in: [0x00, 0x04]) == UnipolarValue(normalized: 1))
    #expect(trigger.value(in: [0xFF, 0x00]) == UnipolarValue(normalized: 1))
    #expect(trigger.value(in: [0x00, 0x00]) == UnipolarValue(normalized: 0))
    #expect(layout.controls == [.leftTrigger])
  }
}
