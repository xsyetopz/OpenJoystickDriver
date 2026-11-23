import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite
struct RumbleOutputTemplateMessageTests {
  private static let english = Localization(preferredLanguages: ["en-US"])

  private static func describe(_ error: any Error) -> String {
    ControllerRecordSet.problemDescription(
      error,
      document: "record",
      localization: english,
      file: "046d-c21d.plist"
    )
  }

  @Test
  func inputReportNamesFileKeyPathRuleAndFix() {
    let report = ControllerTemplateReport(kind: .input, reportID: 1, length: 8)
    do {
      _ = try RumbleOutputTemplate(target: .hid(report), motors: [.lowFrequency: .init(byte: 1)])
      Issue.record("an input report was accepted")
    } catch {
      #expect(
        Self.describe(error)
          == "046d-c21d.plist, session.rumble.report.kind: A rumble template cannot write an "
          + "input report. Fix: Set report to an output or feature report."
      )
    }
  }

  @Test
  func templateWithoutMotorNamesMotorKeys() {
    do {
      _ = try RumbleOutputTemplate(target: .usb(length: 8), motors: [:])
      Issue.record("a template without a motor was accepted")
    } catch {
      #expect(
        Self.describe(error)
          == "046d-c21d.plist, session.rumble: A rumble template must name at least one motor it "
          + "can drive. Fix: Add lowFrequency, highFrequency, leftTrigger or rightTrigger."
      )
    }
  }

  @Test
  func decodedResendIntervalProblemReadsInChosenLanguage() {
    let json = """
      {"report": {"kind": "USB", "length": 8}, "lowFrequency": {"byte": 1},
        "resendIntervalMilliseconds": 0}
      """
    do {
      _ = try JSONDecoder().decode(
        ControllerRecordDocument.RumbleTemplate.self,
        from: Data(json.utf8)
      )
      Issue.record("a zero resend interval was accepted")
    } catch {
      #expect(
        Self.describe(error)
          == "046d-c21d.plist, session.rumble.resendIntervalMilliseconds: A rumble resend "
          + "interval must be 1...60000 ms. Fix: Set resendIntervalMilliseconds to 1...60000, "
          + "or leave it out."
      )
    }
  }

  @Test
  func emptyFollowUpNamesCountAndFix() {
    do {
      _ = try RumbleOutputTemplate(
        target: .usb(length: 4),
        motors: [.lowFrequency: .init(byte: 1)],
        followUp: []
      )
      Issue.record("an empty followUp was accepted")
    } catch {
      #expect(
        Self.describe(error)
          == "046d-c21d.plist, session.rumble.followUp: A rumble template names 1...4 follow-up "
          + "reports. Fix: List 1...4 reports in followUp, or leave it out."
      )
    }
  }

  @Test
  func shortStopReportNamesStopKey() {
    do {
      _ = try RumbleOutputTemplate(
        target: .usb(length: 4),
        motors: [.lowFrequency: .init(byte: 1)],
        stop: [0xF3, 0x00]
      )
      Issue.record("a short stop report was accepted")
    } catch {
      #expect(
        Self.describe(error)
          == "046d-c21d.plist, session.rumble.stop: Each stop report must cover the whole rumble "
          + "report and start with its report ID. Fix: Give stop as many bytes as report.length, "
          + "starting with the report ID of a numbered report."
      )
    }
  }
}
