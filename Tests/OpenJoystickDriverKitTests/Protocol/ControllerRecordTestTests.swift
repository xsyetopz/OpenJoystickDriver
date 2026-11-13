import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ControllerRecordTestTests {
  /// The bundled Xbox 360 wired pad, whose parser reads a 20-byte report.
  private static let model = ControllerModelID(vendorID: 0x045E, productID: 0x028E)

  /// A transmitted packet, then one input report with A held (button bit 12).
  private static let capture = """
    {"timestamp": 0, "direction": "Tx", "hex": "01 03 00", "length": 3}
    {"timestamp": 1, "direction": "Rx", "length": 20, "hex": "\
    00 14 00 10 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"}

    """

  private var record: ControllerRecord {
    get throws { try #require(ControllerRecordSet.bundled.records[Self.model]) }
  }

  private func state(_ state: ControllerState) throws -> Data { try JSONEncoder().encode(state) }

  @Test
  func matchingStateHasNoDifferences() throws {
    let result = try record.test(
      capture: Data(Self.capture.utf8),
      expectation: state(ControllerState(pressed: [.south]))
    )

    #expect(result.matches)
    #expect(result.inputReports == 1)
  }

  @Test
  func differingFieldIsNamed() throws {
    let result = try record.test(
      capture: Data(Self.capture.utf8),
      expectation: state(ControllerState(pressed: [.east]))
    )

    #expect(!result.matches)
    #expect(result.differences.map(\.field) == ["pressed"])
  }

  @Test
  func badCaptureLineNamesItsLine() throws {
    let capture = Data((Self.capture + "not json\n").utf8)

    #expect {
      try record.test(capture: capture, expectation: state(ControllerState()))
    } throws: { error in
      guard case .capture(let line, _)? = error as? ControllerRecordTestError else { return false }
      return line == 3
    }
  }

  @Test
  func lengthThatDisagreesWithHexIsRefused() throws {
    let capture = Data(#"{"direction": "Rx", "hex": "01 02", "length": 3}"#.utf8)

    #expect {
      try record.test(capture: capture, expectation: state(ControllerState()))
    } throws: { error in
      guard case .capture(1, let problem)? = error as? ControllerRecordTestError else {
        return false
      }
      return problem == "length does not match hex"
    }
  }

  @Test
  func expectationThatIsNotStateIsRefused() throws {
    #expect {
      try record.test(capture: Data(Self.capture.utf8), expectation: Data("[]".utf8))
    } throws: { error in
      guard case .expectation? = error as? ControllerRecordTestError else { return false }
      return true
    }
  }

  @Test
  func captureWithoutInputIsRefused() throws {
    let capture = Data(#"{"direction": "Tx", "hex": "01", "length": 1}"#.utf8)

    #expect {
      try record.test(capture: capture, expectation: state(ControllerState()))
    } throws: { error in
      (error as? ControllerRecordTestError) == .replay(.noInput)
    }
  }

  @Test
  func eachErrorNamesInputsInWords() {
    let model = Self.model
    let errors: [ControllerRecordTestError] = [
      .capture(line: 2, problem: "bad"), .expectation(problem: "bad"), .replay(.noParser),
      .replay(.invalidReport(index: 0)), .replay(.noInput),
    ]

    for error in errors {
      let message = error.message(model: model, capture: "c.jsonl", expectation: "s.json")
      #expect(!message.isEmpty)
      #expect(!message.contains("cli.record"))
    }
    #expect(
      errors[0].message(model: model, capture: "c.jsonl", expectation: "s.json").contains("line 2")
    )
    #expect(
      errors[1].message(model: model, capture: "c.jsonl", expectation: "s.json").contains("s.json")
    )
  }
}
