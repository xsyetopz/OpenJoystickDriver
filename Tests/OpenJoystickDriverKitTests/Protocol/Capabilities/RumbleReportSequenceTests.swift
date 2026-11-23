import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The reports a rumble template sends for one intensity: the motor report, its follow-ups, and
/// the stop report.
struct RumbleReportSequenceTests {
  private static let running = RumbleIntensities(lowFrequency: UnipolarValue(0x8000))
  private static let commit: [UInt8] = [0xFA, 0xFE, 0, 0]
  private static let halt: [UInt8] = [0xF3, 0, 0, 0]

  private static func template(
    followUp: [[UInt8]]? = nil,
    stop: [UInt8]? = nil
  ) throws -> RumbleOutputTemplate {
    try RumbleOutputTemplate(
      target: .usb(length: 4),
      bytes: [0x51, 0, 0, 0],
      motors: [.lowFrequency: .init(byte: 2)],
      followUp: followUp,
      stop: stop
    )
  }

  @Test
  func followUpReportsFollowEachRunningReport() throws {
    let template = try Self.template(followUp: [Self.commit])
    #expect(template.reportSequence(Self.running) == [[0x51, 0, 0x80, 0], Self.commit])
  }

  @Test
  func zeroReportSkipsFollowUps() throws {
    let template = try Self.template(followUp: [Self.commit])
    #expect(template.reportSequence(.off) == [[0x51, 0, 0, 0]])
  }

  @Test
  func stopReportReplacesZeroReport() throws {
    let template = try Self.template(followUp: [Self.commit], stop: Self.halt)
    #expect(template.reportSequence(.off) == [Self.halt])
    #expect(template.reportSequence(Self.running).count == 2)
  }

  @Test
  func numberedReportFollowUpNeedsReportID() {
    let report = ControllerTemplateReport(kind: .output, reportID: 2, length: 3)
    #expect(throws: ControllerRecordProblem.self) {
      _ = try RumbleOutputTemplate(
        target: .hid(report),
        motors: [.lowFrequency: .init(byte: 1)],
        followUp: [[0xFA, 0xFE, 0]]
      )
    }
    #expect(throws: Never.self) {
      _ = try RumbleOutputTemplate(
        target: .hid(report),
        motors: [.lowFrequency: .init(byte: 1)],
        followUp: [[0x02, 0xFA, 0xFE]]
      )
    }
  }

  @Test
  func decoderReadsFollowUpAndStopHex() throws {
    let json = """
      {"report": {"kind": "USB", "length": 4}, "bytes": "51 00 00 00",
        "lowFrequency": {"byte": 2}, "followUp": ["FA FE 00 00"], "stop": "F3 00 00 00"}
      """
    let decoded = try JSONDecoder().decode(
      ControllerRecordDocument.RumbleTemplate.self,
      from: Data(json.utf8)
    )
    #expect(decoded.template.followUp == [Self.commit])
    #expect(decoded.template.stop == Self.halt)
  }
}
