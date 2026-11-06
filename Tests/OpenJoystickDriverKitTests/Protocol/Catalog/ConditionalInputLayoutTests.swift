import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// A layout with one button at the first bit after the report ID byte or, without an ID, byte 1.
private func layout(
  id: Int? = nil,
  length: String = #""atLeast": 2"#,
  control: String = "South",
  extra: String = ""
) -> String {
  let idField = id.map { #""id": \#($0), "# } ?? ""
  return #"{"report": {\#(idField)"length": {\#(length)}}, "#
    + #""buttons": [{"control": "\#(control)", "bitOffset": 8, "bitSize": 1}]\#(extra)}"#
}

private func layouts(_ entries: String...) throws -> ControllerInputLayouts {
  try JSONDecoder().decode(
    ControllerRecordDocument.InputLayouts.self,
    from: Data(#"{"layouts": [\#(entries.joined(separator: ", "))]}"#.utf8)
  ).layouts
}

private func driver(_ entries: String...) throws -> ReportLayoutDriver {
  ReportLayoutDriver(
    layouts: try JSONDecoder().decode(
      ControllerRecordDocument.InputLayouts.self,
      from: Data(#"{"layouts": [\#(entries.joined(separator: ", "))]}"#.utf8)
    ).layouts
  )
}

/// Layout lists whose selectors share a report.
private let overlappingLayouts: [[String]] = [
  [layout(id: 1), layout(id: 1)],
  [layout(), layout()],
  [layout(), layout(id: 1)],
  [layout(id: 1, length: #""exactly": 3"#), layout(id: 1, length: #""atLeast": 3"#)],
  [layout(length: #""exactly": 2"#), layout(length: #""exactly": 2"#)],
  [layout(length: #""exactly": 4"#), layout(length: #""atLeast": 3"#, control: "East")],
]

/// Layout lists whose selectors never share a report.
private let disjointLayouts: [[String]] = [
  [layout(id: 1), layout(id: 2)],
  [layout(length: #""exactly": 2"#), layout(length: #""exactly": 3"#)],
  [layout(length: #""exactly": 2"#), layout(length: #""atLeast": 3"#, control: "East")],
  [layout(id: 1, length: #""exactly": 3"#), layout(id: 2, length: #""atLeast": 3"#)],
]

@Suite
struct ConditionalInputLayoutTests {
  @Test
  func theLayoutWithTheReportIDDecodesTheReport() throws {
    let driver = try driver(layout(id: 1), layout(id: 2, control: "East"))
    #expect(try driver.parseReport(Data([1, 1]))?.state == snapshot(.press(.south)))
    driver.resetProtocolState()
    #expect(try driver.parseReport(Data([2, 1]))?.state == snapshot(.press(.east)))
  }

  @Test
  func theLengthRuleSelectsTheLayout() throws {
    let driver = try driver(
      layout(length: #""exactly": 2"#),
      layout(length: #""atLeast": 3"#, control: "East")
    )
    #expect(try driver.parseReport(Data([0, 1]))?.state == snapshot(.press(.south)))
    driver.resetProtocolState()
    #expect(try driver.parseReport(Data([0, 1, 0]))?.state == snapshot(.press(.east)))
    driver.resetProtocolState()
    #expect(try driver.parseReport(Data([0, 1, 0, 0, 0]))?.state == snapshot(.press(.east)))
    #expect(try driver.parseReport(Data([0])) == nil)
  }

  @Test(arguments: overlappingLayouts)
  func rejectsLayoutsThatSelectTheSameReport(entries: [String]) {
    #expect(throws: DecodingError.self) { try layouts(entries[0], entries[1]) }
  }

  @Test(arguments: disjointLayouts)
  func acceptsLayoutsThatSelectDifferentReports(entries: [String]) throws {
    #expect(try layouts(entries[0], entries[1]).layouts.count == 2)
  }

  @Test
  func aReportNoLayoutSelectsIsIgnored() throws {
    let driver = try driver(layout(id: 1), layout(id: 2, control: "East"))
    #expect(try driver.parseReport(Data([3, 1])) == nil)
    #expect(try driver.parseReport(Data([1])) == nil)
    #expect(try driver.parseReport(Data()) == nil)
  }

  @Test
  func aLayoutChangesOnlyTheControlsItNames() throws {
    let driver = try driver(
      layout(
        id: 1,
        length: #""atLeast": 3"#,
        extra: ##", "axes": [{"control": "LeftStickX", "bitOffset": 16, "bitSize": 8}]"##
      ),
      layout(id: 2, control: "East")
    )
    let first = try driver.parseReport(Data([1, 1, 0xFF]))?.state
    #expect(first?.pressed == [.south])
    #expect(first?.leftStick.x.normalized == 1)
    let second = try driver.parseReport(Data([2, 1]))?.state
    #expect(second?.pressed == [.south, .east])
    #expect(second?.leftStick.x.normalized == 1)
    let third = try driver.parseReport(Data([2, 0]))?.state
    #expect(third?.pressed == [.south])
    #expect(third?.leftStick.x.normalized == 1)
  }

  @Test
  func theRecordsControlsAreTheUnionAcrossLayouts() throws {
    let all = try layouts(layout(id: 1), layout(id: 2, control: "East"))
    #expect(all.controls == [.south, .east])
  }

  @Test
  func rejectsAnEmptyListAndUnknownKeys() {
    let decode = { (json: String) throws in
      try JSONDecoder().decode(ControllerRecordDocument.InputLayouts.self, from: Data(json.utf8))
    }
    #expect(throws: DecodingError.self) { try decode(#"{"layouts": []}"#) }
    #expect(throws: DecodingError.self) { try decode(#"{}"#) }
    #expect(throws: DecodingError.self) {
      try decode(#"{"layouts": [\#(layout())], "report": {}}"#)
    }
  }

  @Test
  func aLayoutLongerThanTheCeilingIsRejected() {
    #expect(throws: DecodingError.self) {
      try layouts(layout(length: #""atLeast": 65"#))
    }
    #expect(throws: Never.self) {
      try layouts(layout(length: #""atLeast": 64"#))
    }
  }
}
