import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// One valid button, for cases that vary only another part of the layout.
private let button = #"{"control": "face-south", "byte": 1, "mask": 1}"#

@Suite
struct ControllerInputLayoutTests {
  @Test
  func repeatedButtonFieldsAreAlternatives() throws {
    let layout = try inputLayout(
      """
      {"report": {"length": 2}, "buttons": [
        {"control": "face-north", "byte": 0, "mask": 8},
        {"control": "face-north", "byte": 1, "mask": 128}
      ]}
      """
    )
    #expect(layout.buttons.count == 1)
    #expect(
      layout.buttons.first?.fields == [
        ReportBitField(byte: 0, mask: 8), ReportBitField(byte: 1, mask: 128),
      ]
    )
    #expect(layout.controls == [.faceNorth])
  }

  @Test
  func opposingDirectionsCancel() throws {
    let layout = try inputLayout(
      """
      {"report": {"length": 1}, "hat": [{"encoding": "directions",
        "up": {"byte": 0, "mask": 1}, "right": {"byte": 0, "mask": 2},
        "down": {"byte": 0, "mask": 4}, "left": {"byte": 0, "mask": 8}}]}
      """
    )
    let driver = ReportLayoutDriver(layout: layout)
    #expect(try driver.parseReport(Data([0x05]))?.state == .neutral)
    #expect(try driver.parseReport(Data([0x07])).contains(.hat(.east)))
    #expect(layout.controls == [.dpad])
  }

  @Test(
    arguments: [
      // Report bounds.
      #"{"report": {"id": 0, "length": 2}, "buttons": [\#(button)]}"#,
      #"{"report": {"id": 256, "length": 2}, "buttons": [\#(button)]}"#,
      #"{"report": {"length": 0}, "buttons": [\#(button)]}"#,
      #"{"report": {"length": 65}, "buttons": [\#(button)]}"#,
      #"{"report": {"id": 1, "length": 1}, "buttons": [\#(button)]}"#,
      // Fields.
      #"{"report": {"length": 2}, "buttons": [{"control": "face-south", "byte": 1, "mask": 0}]}"#,
      #"{"report": {"length": 2}, "buttons": [{"control": "face-south", "byte": 1, "mask": 256}]}"#,
      #"{"report": {"length": 2}, "buttons": [{"control": "face-south", "byte": 2, "mask": 1}]}"#,
      #"{"report": {"id": 1, "length": 2}, "#
        + #""buttons": [{"control": "face-south", "byte": 0, "mask": 1}]}"#,
      #"{"report": {"length": 2}, "buttons": [{"control": "dpad", "byte": 1, "mask": 1}]}"#,
      #"{"report": {"length": 2}, "buttons": [{"control": "left-trigger", "byte": 1, "mask": 1}]}"#,
      // Hat.
      #"{"report": {"length": 2}, "hat": [{"encoding": "8-way", "byte": 1, "mask": 3}]}"#,
      #"{"report": {"length": 2}, "hat": [{"encoding": "8-way", "byte": 1, "mask": 11}]}"#,
      #"{"report": {"length": 2}, "hat": [{"encoding": "4-way", "byte": 1, "mask": 15}]}"#,
      // Axes.
      #"{"report": {"length": 2}, "axes": [{"control": "face-south", "byte": 1}]}"#,
      #"{"report": {"length": 3}, "axes": [{"control": "left-stick-x", "byte": 1}, "#
        + #"{"control": "left-stick-x", "byte": 2}]}"#,
      #"{"report": {"length": 3}, "axes": [{"control": "left-stick-x", "byte": 1, "bits": 12}]}"#,
      #"{"report": {"length": 2}, "axes": [{"control": "left-stick-x", "byte": 1, "bits": 16}]}"#,
      #"{"report": {"length": 2}, "#
        + #""axes": [{"control": "left-stick-x", "byte": 1, "min": 10, "max": 11}]}"#,
      #"{"report": {"length": 2}, "axes": [{"control": "left-stick-x", "byte": 1, "max": 256}]}"#,
      // Triggers and shape.
      #"{"report": {"length": 2}, "leftTrigger": {}}"#,
      #"{"report": {"length": 2}}"#,
      #"{"report": {"length": 2}, "buttons": []}"#,
      #"{"report": {"length": 2}, "buttons": [\#(button)], "touchpad": {}}"#,
      #"{"report": {"length": 2, "endpoint": 1}, "buttons": [\#(button)]}"#,
    ]
  )
  func rejectsInvalidLayouts(json: String) {
    #expect(throws: DecodingError.self) { try inputLayout(json) }
  }
}
