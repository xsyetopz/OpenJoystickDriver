import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// One valid button, for cases that vary only another part of the layout.
private let button = #"{"control": "South", "bitOffset": 8, "bitSize": 1}"#

/// Layouts the symmetric axis and table hat rules reject.
private let invalidSymmetricAxesAndTableHats: [String] = [
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""axes": [{"control": "LeftStickX", "bitOffset": 8, "bitSize": 8, "symmetric": true}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""axes": [{"control": "LeftStickX", "bitOffset": 8, "bitSize": 8, "signed": true, "#
    + #""min": 0, "max": 127, "symmetric": true}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""hat": [{"encoding": "Table", "bitOffset": 8, "bitSize": 4, "#
    + #""values": {}}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""hat": [{"encoding": "Table", "bitOffset": 8, "bitSize": 4, "#
    + #""values": {"16": "North"}}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""hat": [{"encoding": "Table", "bitOffset": 8, "bitSize": 4, "#
    + #""values": {"01": "North"}}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""hat": [{"encoding": "Table", "bitOffset": 8, "bitSize": 4, "#
    + #""values": {"1": "Neutral"}}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""hat": [{"encoding": "Table", "bitOffset": 8, "bitSize": 4, "#
    + #""values": {"1": "up"}}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""hat": [{"encoding": "Table", "bitOffset": 8, "bitSize": 4}]}"#,
]

/// Layouts the decoder rejects.
private let invalidLayouts: [String] = [
  // Report bounds.
  #"{"report": {"id": 0, "length": {"atLeast": 2}}, "buttons": [\#(button)]}"#,
  #"{"report": {"id": 256, "length": {"atLeast": 2}}, "buttons": [\#(button)]}"#,
  #"{"report": {"length": {"atLeast": 0}}, "buttons": [\#(button)]}"#,
  #"{"report": {"length": {"atLeast": 65}}, "buttons": [\#(button)]}"#,
  #"{"report": {"id": 1, "length": {"atLeast": 1}}, "buttons": [\#(button)]}"#,
  #"{"report": {"length": {"exactly": 0}}, "buttons": [\#(button)]}"#,
  #"{"report": {"length": {"exactly": 65}}, "buttons": [\#(button)]}"#,
  #"{"report": {"id": 1, "length": {"exactly": 1}}, "buttons": [\#(button)]}"#,
  // The length rule names exactly one of atLeast and exactly.
  #"{"report": {"length": 2}, "buttons": [\#(button)]}"#,
  #"{"report": {}, "buttons": [\#(button)]}"#,
  #"{"report": {"length": {}}, "buttons": [\#(button)]}"#,
  #"{"report": {"length": {"atLeast": 2, "exactly": 2}}, "buttons": [\#(button)]}"#,
  #"{"report": {"length": {"atLeast": 2}, "exactLength": true}, "buttons": [\#(button)]}"#,
  // Fields.
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""buttons": [{"control": "South", "bitOffset": 8, "bitSize": 0}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""buttons": [{"control": "South", "bitOffset": 16, "bitSize": 1}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""buttons": [{"control": "South", "bitOffset": 16, "bitSize": 1}]}"#,
  #"{"report": {"id": 1, "length": {"atLeast": 2}}, "#
    + #""buttons": [{"control": "South", "bitOffset": 0, "bitSize": 1}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""buttons": [{"control": "DpadUp", "bitOffset": 8, "bitSize": 1}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""buttons": [{"control": "LeftStickX", "bitOffset": 8, "bitSize": 1}]}"#,
  // Hat.
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""hat": [{"encoding": "EightWay", "bitOffset": 8, "bitSize": 2}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""hat": [{"encoding": "4-way", "bitOffset": 8, "bitSize": 4}]}"#,
  // Axes.
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""axes": [{"control": "South", "bitOffset": 8, "bitSize": 8}]}"#,
  #"{"report": {"length": {"atLeast": 3}}, "#
    + #""axes": [{"control": "LeftStickX", "bitOffset": 8, "bitSize": 8}, "#
    + #"{"control": "LeftStickX", "bitOffset": 16, "bitSize": 8}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""axes": [{"control": "LeftStickX", "bitOffset": 8, "bitSize": 16}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""axes": [{"control": "LeftStickX", "bitOffset": 8, "bitSize": 8, "min": 10, "max": 11}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""axes": [{"control": "LeftStickX", "bitOffset": 8, "bitSize": 8, "max": 256}]}"#,
  // Triggers and shape.
  #"{"report": {"length": {"atLeast": 2}}, "leftTrigger": {}}"#,
  #"{"report": {"length": {"atLeast": 2}}}"#,
  #"{"report": {"length": {"atLeast": 2}}, "buttons": []}"#,
  #"{"report": {"length": {"atLeast": 2}}, "buttons": [\#(button)], "touchpad": {}}"#,
  #"{"report": {"length": {"atLeast": 2}, "endpoint": 1}, "buttons": [\#(button)]}"#,
]

@Suite
struct ControllerInputLayoutTests {
  @Test
  func repeatedButtonFieldsAreAlternatives() throws {
    let layout = try inputLayout(
      """
      {"report": {"length": {"atLeast": 2}}, "buttons": [
        {"control": "North", "bitOffset": 3, "bitSize": 1},
        {"control": "North", "bitOffset": 15, "bitSize": 1}
      ]}
      """
    )
    #expect(layout.buttons.count == 1)
    #expect(
      layout.buttons.first?.fields == [
        ReportBitField(bitOffset: 3, bitSize: 1), ReportBitField(bitOffset: 15, bitSize: 1),
      ]
    )
    #expect(layout.controls == [.north])
  }

  @Test
  func exactlyIgnoresLongerReportsAndAtLeastAcceptsThem() throws {
    let exact = try layoutDriver(
      try inputLayout(
        """
        {"report": {"length": {"exactly": 2}},
          "buttons": [{"control": "South", "bitOffset": 8, "bitSize": 1}]}
        """
      )
    )
    #expect(try exact.parseReport(Data([0, 1]))?.state.pressed == [.south])
    #expect(try exact.parseReport(Data([0, 1, 0])) == nil)
    #expect(try exact.parseReport(Data([0])) == nil)
    let atLeast = try layoutDriver(
      try inputLayout(
        """
        {"report": {"length": {"atLeast": 2}},
          "buttons": [{"control": "South", "bitOffset": 8, "bitSize": 1}]}
        """
      )
    )
    #expect(try atLeast.parseReport(Data([0, 1, 0]))?.state.pressed == [.south])
  }

  @Test
  func opposingDirectionsCancel() throws {
    let layout = try inputLayout(
      """
      {"report": {"length": {"atLeast": 1}}, "hat": [{"encoding": "Directions",
        "up": {"bitOffset": 0, "bitSize": 1}, "right": {"bitOffset": 1, "bitSize": 1},
        "down": {"bitOffset": 2, "bitSize": 1}, "left": {"bitOffset": 3, "bitSize": 1}}]}
      """
    )
    let driver = try layoutDriver(layout)
    #expect(try driver.parseReport(Data([0x05]))?.state == .neutral)
    #expect(try driver.parseReport(Data([0x07])).contains(.hat(.east)))
    #expect(layout.controls == Control.dpad)
  }

  @Test
  func aTableHatNamesDirectionsForMaskedValues() throws {
    let layout = try inputLayout(
      """
      {"report": {"length": {"atLeast": 1}},
        "hat": [{"encoding": "Table", "bitOffset": 4, "bitSize": 4,
        "values": {"1": "North", "9": "NorthEast"}}]}
      """
    )
    let driver = try layoutDriver(layout)
    #expect(try driver.parseReport(Data([0x10]))?.state.hat == .north)
    #expect(try driver.parseReport(Data([0x9F]))?.state.hat == .northEast)
    #expect(try driver.parseReport(Data([0x20]))?.state.hat == .neutral)
    #expect(layout.controls == Control.dpad)
  }

  @Test
  func aSymmetricAxisDividesBothSidesByTheMaximum() throws {
    let layout = try inputLayout(
      """
      {"report": {"length": {"atLeast": 2}},
        "axes": [{"control": "LeftStickX", "bitOffset": 0, "bitSize": 16,
          "signed": true, "min": -32768, "max": 32767, "symmetric": true}]}
      """
    )
    let driver = try layoutDriver(layout)
    #expect(try driver.parseReport(Data([0x00, 0x80]))?.state.leftStick.x.normalized == -1)
    #expect(try driver.parseReport(Data([0x01, 0x80]))?.state.leftStick.x.normalized == -1)
    #expect(try driver.parseReport(Data([0xFF, 0x7F]))?.state.leftStick.x.normalized == 1)
    #expect(try driver.parseReport(Data([0x00, 0x00]))?.state.leftStick.x.normalized == 0)
  }

  @Test
  func aSymmetricAxisWithoutRangeUsesTheFullRange() throws {
    let layout = try inputLayout(
      """
      {"report": {"length": {"atLeast": 2}},
        "axes": [{"control": "LeftStickX", "bitOffset": 0, "bitSize": 16,
          "signed": true, "symmetric": true}]}
      """
    )
    let driver = try layoutDriver(layout)
    #expect(try driver.parseReport(Data([0x00, 0x80]))?.state.leftStick.x.normalized == -1)
    #expect(try driver.parseReport(Data([0xFF, 0x7F]))?.state.leftStick.x.normalized == 1)
    #expect(try driver.parseReport(Data([0x00, 0x00]))?.state.leftStick.x.normalized == 0)
  }

  @Test(arguments: invalidSymmetricAxesAndTableHats)
  func rejectsInvalidSymmetricAxesAndTableHats(json: String) {
    #expect(throws: DecodingError.self) { try inputLayout(json) }
  }

  @Test(arguments: invalidLayouts)
  func rejectsInvalidLayouts(json: String) {
    #expect(throws: DecodingError.self) { try inputLayout(json) }
  }

  @Test
  func decodedLayoutProblemReadsInChosenLanguage() {
    let english = Localization(preferredLanguages: ["en-US"])
    do {
      _ = try inputLayout(
        #"{"report": {"length": {"atLeast": 3}}, "axes": ["#
          + #"{"control": "LeftStickX", "bitOffset": 8, "bitSize": 8}, "#
          + #"{"control": "LeftStickX", "bitOffset": 16, "bitSize": 8}]}"#
      )
      Issue.record("two axes of one control were accepted")
    } catch {
      #expect(
        ControllerRecordSet.problemDescription(
          error,
          document: "record",
          localization: english,
          file: "046d-c21d.plist"
        )
          == "046d-c21d.plist, input.layouts[].axes: Axes must name distinct stick axes. "
          + "Fix: Name each stick axis once."
      )
    }
  }

  @Test
  func messagesNameFileKeyPathRuleAndFix() {
    let english = Localization(preferredLanguages: ["en-US"])
    func message(reportID: UInt8?, minimumLength: Int) -> String? {
      do {
        _ = try ControllerInputLayout(
          reportID: reportID,
          minimumLength: minimumLength,
          requiresExactLength: false,
          buttons: [(.south, ReportBitField(bitOffset: 8, bitSize: 1))],
          axes: [],
          hat: [],
          leftTrigger: nil,
          rightTrigger: nil
        )
        return nil
      } catch {
        return error.localizedDescription(english, file: "046d-c21d.plist")
      }
    }
    #expect(
      message(reportID: 0, minimumLength: 2)
        == "046d-c21d.plist, input.layouts[].report.id: A report ID is 1...255. "
        + "Fix: Set the ID to a whole number from 1 to 255, or leave it out."
    )
    #expect(
      message(reportID: nil, minimumLength: 65)
        == "046d-c21d.plist, input.layouts[].report.length: "
        + "A report is 1...64 bytes long, with its ID byte. Fix: Set the length inside that range."
    )
    do {
      _ = try ControllerInputLayouts(layouts: [])
      Issue.record("an empty layout list was accepted")
    } catch {
      #expect(
        error.localizedDescription(english, file: "046d-c21d.plist")
          == "046d-c21d.plist, input.layouts: Input must list at least one layout. "
          + "Fix: Add a layout, or delete input."
      )
    }
  }
}
