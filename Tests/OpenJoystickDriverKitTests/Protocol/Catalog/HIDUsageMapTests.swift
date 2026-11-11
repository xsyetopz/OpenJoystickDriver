import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Button, axis and hat usages as typed data: how a record declares them and what each reads.
struct HIDUsageMapTests {
  private func element(
    page: UInt32 = 1,
    usage: UInt32,
    _ value: Int,
    range: ClosedRange<Int> = 0...255,
    reportID: UInt32? = nil
  ) -> HIDElementValue {
    HIDElementValue(
      usagePage: page,
      usage: usage,
      logicalMinimum: range.lowerBound,
      logicalMaximum: range.upperBound,
      integerValue: value,
      reportID: reportID
    )
  }

  private func makeDriver(_ entries: String, reportID: Int? = nil) throws -> HIDDescriptorDriver {
    let document = try decode(entries, reportID: reportID)
    return HIDDescriptorDriver(
      model: ControllerModelID(vendorID: 0xFFFE, productID: 1),
      usageMap: document.hidUsageMap
    )
  }

  private func state(_ driver: HIDDescriptorDriver, _ value: HIDElementValue) -> ControllerState? {
    driver.parse(elementValue: value, receivedAt: MonotonicTimestamp(nanoseconds: 0))?.state
  }

  private func decode(
    _ entries: String,
    reportID: Int? = nil,
    family: String = "HIDDescriptor",
    key: String = "hidUsageMap"
  ) throws -> ControllerRecordDocument {
    let report = reportID.map { "\"reportID\": \($0)," } ?? ""
    let json = """
      {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "\(ControllerRecordDocument.kind)",
        "vendorID": 65534, "productID": 1,
      "modes": [{"id": "default", "protocol": {"family": "\(family)"}}],
      "input": {"\(key)": {\(report) "usages": [\(entries)]}}}
      """
    return try JSONDecoder().decode(ControllerRecordDocument.self, from: Data(json.utf8))
  }

  // MARK: - Buttons

  @Test
  func aButtonUsagePressesItsControlWhileNonzero() throws {
    let driver = try makeDriver(#"{"kind":"Button","page":9,"usage":3,"control":"West"}"#)
    #expect(
      state(driver, element(page: 9, usage: 3, 1, range: 0...1))?.pressed.contains(.west)
        == true
    )
    #expect(
      state(driver, element(page: 9, usage: 3, 0, range: 0...1))?.pressed.contains(.west)
        == false
    )
    #expect(state(driver, element(page: 9, usage: 4, 1, range: 0...1)) == nil)
    #expect(state(driver, element(page: 8, usage: 3, 1, range: 0...1)) == nil)
  }

  @Test
  func aReportIDRestrictsTheMapToThatReport() throws {
    let driver = try makeDriver(
      #"{"kind":"Button","page":9,"usage":1,"control":"South"}"#,
      reportID: 6
    )
    #expect(state(driver, element(page: 9, usage: 1, 1, range: 0...1, reportID: 5)) == nil)
    #expect(state(driver, element(page: 9, usage: 1, 1, range: 0...1, reportID: nil)) == nil)
    #expect(
      state(driver, element(page: 9, usage: 1, 1, range: 0...1, reportID: 6))?.pressed.contains(
        .south
      )
        == true
    )
  }

  // MARK: - Axes

  private func axisEntry(control: String, _ options: String = "") -> String {
    #"{"kind":"Axis","page":1,"usage":48,"control":"\#(control)"\#(options)}"#
  }

  @Test
  func aStickAxisScalesTheLogicalRangeToMinusOneToOne() throws {
    let driver = try makeDriver(axisEntry(control: "LeftStickX"))
    #expect(state(driver, element(usage: 48, 255))?.leftStick.x.normalized == 1)
    #expect(state(driver, element(usage: 48, 0))?.leftStick.x.normalized == -1)
    #expect(
      abs(try #require(state(driver, element(usage: 48, 128))?.leftStick.x.normalized)) < 0.01
    )
  }

  @Test
  func anInvertedStickNegatesTheAxis() throws {
    let driver = try makeDriver(axisEntry(control: "LeftStickX", #","inverted":true"#))
    #expect(state(driver, element(usage: 48, 255))?.leftStick.x.normalized == -1)
    #expect(state(driver, element(usage: 48, 0))?.leftStick.x.normalized == 1)
  }

  @Test
  func anAxisRangeOverridesTheElementsLogicalRange() throws {
    let driver = try makeDriver(
      axisEntry(control: "LeftStickX", #","range":{"min":0,"max":100}"#)
    )
    // The element declares 0...255; the record says full deflection is 100.
    #expect(state(driver, element(usage: 48, 100))?.leftStick.x.normalized == 1)
    #expect(state(driver, element(usage: 48, 200))?.leftStick.x.normalized == 1)
    #expect(state(driver, element(usage: 48, 0))?.leftStick.x.normalized == -1)
  }

  @Test
  func aStickDeadZoneReadsZeroInsideAndRescalesOutside() throws {
    let driver = try makeDriver(
      axisEntry(control: "LeftStickX", #","range":{"min":-100,"max":100},"deadZone":0.2"#)
    )
    let wide = -100...100
    #expect(state(driver, element(usage: 48, 10, range: wide))?.leftStick.x.normalized == 0)
    #expect(state(driver, element(usage: 48, -20, range: wide))?.leftStick.x.normalized == 0)
    #expect(state(driver, element(usage: 48, 100, range: wide))?.leftStick.x.normalized == 1)
    let half = try #require(
      state(driver, element(usage: 48, 60, range: wide))?.leftStick.x.normalized
    )
    #expect(abs(half - 0.5) < 0.001)
  }

  @Test
  func aTriggerAxisReadsZeroToOneAndSupportsInversionAndDeadZone() throws {
    let plain = try makeDriver(axisEntry(control: "RightTrigger"))
    #expect(state(plain, element(usage: 48, 255))?.rightTrigger.normalized == 1)
    #expect(state(plain, element(usage: 48, 0))?.rightTrigger.normalized == 0)

    let inverted = try makeDriver(axisEntry(control: "LeftTrigger", #","inverted":true"#))
    #expect(state(inverted, element(usage: 48, 0))?.leftTrigger.normalized == 1)
    #expect(state(inverted, element(usage: 48, 255))?.leftTrigger.normalized == 0)

    let dead = try makeDriver(axisEntry(control: "LeftTrigger", #","deadZone":0.5"#))
    #expect(state(dead, element(usage: 48, 100))?.leftTrigger.normalized == 0)
    #expect(state(dead, element(usage: 48, 255))?.leftTrigger.normalized == 1)
  }

  /// Spec scenario "Swapped trigger axes": a record maps usage Z to the right trigger.
  @Test
  func swappedTriggerAxesFollowTheRecord() throws {
    let driver = try makeDriver(
      #"{"kind":"Axis","page":1,"usage":50,"control":"RightTrigger"},"#
        + #"{"kind":"Axis","page":1,"usage":53,"control":"LeftTrigger"}"#
    )
    let pulled = state(driver, element(usage: 50, 255))
    #expect(pulled?.rightTrigger.normalized == 1)
    #expect(pulled?.leftTrigger.normalized == 0)
  }

  @Test
  func anAxisWithNoSpanReadsZero() throws {
    let driver = try makeDriver(axisEntry(control: "LeftStickX"))
    #expect(state(driver, element(usage: 48, 5, range: 0...0))?.leftStick.x.normalized == 0)
  }

  // MARK: - Hats

  private let hatEntry = #"{"kind":"Hat","page":1,"usage":57}"#

  @Test
  func aHatReadsFromTheElementsLogicalMinimumByDefault() throws {
    let driver = try makeDriver(hatEntry)
    #expect(state(driver, element(usage: 57, 0, range: 0...7))?.hat == .north)
    #expect(state(driver, element(usage: 57, 3, range: 0...7))?.hat == .southEast)
    #expect(state(driver, element(usage: 57, 1, range: 1...8))?.hat == .north)
    #expect(state(driver, element(usage: 57, 8, range: 1...8))?.hat == .northWest)
    #expect(state(driver, element(usage: 57, 15, range: 0...7))?.hat == .neutral)
  }

  @Test(arguments: [(0, 8), (1, 9)])
  func aHatRangeNamesWhereNorthIs(first: Int, nullValue: Int) throws {
    let range = "{\"min\":\(first),\"max\":\(first + 7)}"
    let driver = try makeDriver(
      #"{"kind":"Hat","page":1,"usage":57,"range":\#(range)}"#
    )
    #expect(state(driver, element(usage: 57, first, range: 0...15))?.hat == .north)
    #expect(state(driver, element(usage: 57, first + 4, range: 0...15))?.hat == .south)
    #expect(state(driver, element(usage: 57, first + 7, range: 0...15))?.hat == .northWest)
    #expect(state(driver, element(usage: 57, nullValue, range: 0...15))?.hat == .neutral)
  }

  // MARK: - Rejections

  @Test
  func theDecoderRejectsInvalidUsages() {
    let button = #"{"kind":"Button","page":9,"usage":1,"control":"South"}"#
    let invalid = [
      // The same usage twice.
      button + "," + button,
      // A button cannot drive a stick axis or the dpad.
      #"{"kind":"Button","page":9,"usage":1,"control":"LeftStickX"}"#,
      #"{"kind":"Button","page":9,"usage":1,"control":"DpadUp"}"#,
      // An axis needs a stick axis or trigger.
      #"{"kind":"Axis","page":1,"usage":48,"control":"South"}"#,
      #"{"kind":"Axis","page":1,"usage":48,"control":"DpadUp"}"#,
      // A hat has no control: it is the four dpad ids.
      #"{"kind":"Hat","page":1,"usage":57,"control":"DpadUp"}"#,
      // Ranges must have min below max, and a hat range is 0...7 or 1...8.
      #"{"kind":"Axis","page":1,"usage":48,"control":"LeftStickX","range":{"min":5,"max":5}}"#,
      #"{"kind":"Axis","page":1,"usage":48,"control":"LeftStickX","range":{"min":9,"max":1}}"#,
      #"{"kind":"Hat","page":1,"usage":57,"range":{"min":2,"max":9}}"#,
      // A dead zone is above 0 and below 1.
      #"{"kind":"Axis","page":1,"usage":48,"control":"LeftStickX","deadZone":0}"#,
      #"{"kind":"Axis","page":1,"usage":48,"control":"LeftStickX","deadZone":1}"#,
      #"{"kind":"Axis","page":1,"usage":48,"control":"LeftStickX","deadZone":-0.1}"#,
      // Fields that belong to another kind, unknown kinds and unknown fields.
      #"{"kind":"Button","page":9,"usage":1,"control":"South","deadZone":0.1}"#,
      #"{"kind":"Hat","page":1,"usage":57,"inverted":true}"#,
      #"{"kind":"slider","page":1,"usage":48,"control":"LeftStickX"}"#,
      #"{"kind":"Button","page":9,"usage":1,"control":"South","extra":1}"#,
      // Page and usage bounds.
      #"{"kind":"Button","page":0,"usage":1,"control":"South"}"#,
      #"{"kind":"Button","page":9,"usage":65536,"control":"South"}"#,
      "",
    ]
    for entries in invalid {
      #expect(throws: (any Error).self, "\(entries)") { try decode(entries) }
    }
    #expect(throws: (any Error).self) { try decode(button, reportID: 0) }
    #expect(throws: (any Error).self) { try decode(button, reportID: 256) }
  }

  @Test
  func aUsageMapBelongsToHIDDescriptorRecordsOnly() throws {
    let button = #"{"kind":"Button","page":9,"usage":1,"control":"South"}"#
    #expect(try decode(button).hidUsageMap?.entries.count == 1)
    #expect(throws: (any Error).self) { try decode(button, family: "SonyDualShock4") }
    #expect(throws: (any Error).self) { try decode(button, family: "HIDReportLayout") }
    #expect(throws: (any Error).self) { try decode(button, key: "descriptorShapes") }
  }

  // MARK: - Half axes, axis buttons and button triggers

  private func half(
    _ kind: String,
    _ half: String,
    _ control: String,
    _ options: String = ""
  ) -> String {
    #"{"kind":"\#(kind)","page":1,"usage":50,"half":"\#(half)","control":"\#(control)"\#(options)}"#
  }

  private func z(_ value: Int) -> HIDElementValue { element(usage: 50, value, range: -100...100) }

  @Test
  func aCombinedTriggerAxisReadsEachHalfAsOneTrigger() throws {
    let driver = try makeDriver(
      half("HalfAxis", "Positive", "LeftTrigger") + ","
        + half("HalfAxis", "Negative", "RightTrigger")
    )
    let high = try #require(state(driver, z(100)))
    #expect(high.leftTrigger.normalized == 1 && high.rightTrigger.normalized == 0)
    let low = try #require(state(driver, z(-100)))
    #expect(low.leftTrigger.normalized == 0 && low.rightTrigger.normalized == 1)
    let middle = try #require(state(driver, z(0)))
    #expect(middle.leftTrigger.normalized == 0 && middle.rightTrigger.normalized == 0)
    let quarter = try #require(state(driver, z(50)))
    #expect(abs(quarter.leftTrigger.normalized - 0.5) < 0.01)
  }

  @Test
  func aHalfAxisMayBeInverted() throws {
    let driver = try makeDriver(half("HalfAxis", "Positive", "LeftTrigger", #","inverted":true"#))
    #expect(state(driver, z(100))?.leftTrigger.normalized == 0)
    #expect(state(driver, z(0))?.leftTrigger.normalized == 1)
  }

  @Test
  func anAxisDpadPressesTheDirectionAtOrPastTheThreshold() throws {
    let driver = try makeDriver(
      half("AxisDpad", "Negative", "DpadLeft", #","threshold":0.5"#)
    )
    #expect(state(driver, z(-60))?.hat == .west)
    #expect(state(driver, z(-50))?.hat == .west)
    #expect(state(driver, z(-40))?.hat == .neutral)
    #expect(state(driver, z(60))?.hat == .neutral)
  }

  @Test
  func anAxisAndAHatDriveTheSameDirectionTogether() throws {
    let driver = try makeDriver(
      half("AxisDpad", "Negative", "DpadLeft", #","threshold":0.5"#)
        + #",{"kind":"Hat","page":1,"usage":57}"#
    )
    #expect(state(driver, element(usage: 57, 0, range: 0...7))?.hat == .north)
    #expect(state(driver, z(-60))?.hat == .northWest)
    #expect(state(driver, element(usage: 57, 8, range: 0...7))?.hat == .west)
    #expect(state(driver, z(0))?.hat == .neutral)
  }

  @Test
  func anAxisButtonPressesTheButtonAtOrPastTheThreshold() throws {
    let driver = try makeDriver(
      half("AxisButton", "Positive", "East", #","threshold":0.75"#)
    )
    #expect(state(driver, z(80))?.pressed.contains(.east) == true)
    #expect(state(driver, z(75))?.pressed.contains(.east) == true)
    #expect(state(driver, z(70))?.pressed.contains(.east) == false)
    #expect(state(driver, z(-100))?.pressed.contains(.east) == false)
  }

  @Test
  func aButtonTriggerReadsOneWhileTheButtonIsNonzero() throws {
    let driver = try makeDriver(
      #"{"kind":"ButtonTrigger","page":9,"usage":7,"control":"RightTrigger"}"#
    )
    #expect(
      state(driver, element(page: 9, usage: 7, 1, range: 0...1))?.rightTrigger.normalized == 1
    )
    #expect(
      state(driver, element(page: 9, usage: 7, 0, range: 0...1))?.rightTrigger.normalized == 0
    )
  }

  @Test
  func bothHalvesOfOneUsageAreAccepted() throws {
    let entries =
      half("HalfAxis", "Positive", "LeftTrigger") + ","
      + half("AxisDpad", "Negative", "DpadLeft", #","threshold":0.5"#)
    #expect(try decode(entries).hidUsageMap?.entries.count == 2)
    #expect(
      try makeDriver(entries).capabilities.controls.isSuperset(of: [.leftTrigger, .dpadLeft])
    )
  }

  @Test
  func theDecoderRejectsInvalidHalfBindings() {
    let invalid = [
      // A missing, zero or full threshold.
      half("AxisButton", "Positive", "East"),
      half("AxisDpad", "Positive", "DpadUp"),
      half("AxisButton", "Positive", "East", #","threshold":0"#),
      half("AxisButton", "Positive", "East", #","threshold":1"#),
      // The same half twice, in one kind or across kinds.
      half("HalfAxis", "Positive", "LeftTrigger") + ","
        + half("HalfAxis", "Positive", "RightTrigger"),
      half("HalfAxis", "Positive", "LeftTrigger") + ","
        + half("AxisButton", "Positive", "East", #","threshold":0.5"#),
      // A whole axis, a hat or a button trigger next to a half of the same usage.
      #"{"kind":"Axis","page":1,"usage":50,"control":"LeftStickX"},"#
        + half("HalfAxis", "Positive", "LeftTrigger"),
      half("HalfAxis", "Positive", "LeftTrigger")
        + #",{"kind":"ButtonTrigger","page":1,"usage":50,"control":"RightTrigger"}"#,
      // A control of the wrong kind, an unknown half and a key of another kind.
      half("HalfAxis", "Positive", "South"),
      half("AxisDpad", "Positive", "South", #","threshold":0.5"#),
      half("AxisButton", "Positive", "DpadUp", #","threshold":0.5"#),
      half("AxisButton", "Positive", "LeftStickX", #","threshold":0.5"#),
      half("HalfAxis", "Both", "LeftTrigger"),
      half("HalfAxis", "Positive", "LeftTrigger", #","threshold":0.5"#),
      #"{"kind":"ButtonTrigger","page":9,"usage":7,"control":"South"}"#,
      #"{"kind":"ButtonTrigger","page":9,"usage":7,"control":"RightTrigger","half":"Positive"}"#,
    ]
    for entries in invalid {
      #expect(throws: (any Error).self, "\(entries)") { try decode(entries) }
    }
  }
}
