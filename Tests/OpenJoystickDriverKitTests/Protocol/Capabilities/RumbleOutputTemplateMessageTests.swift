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
  func anInputReportNamesFileKeyPathRuleAndFix() {
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
  func aTemplateWithoutAMotorNamesTheMotorKeys() {
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
  func aDecodedResendIntervalProblemReadsInTheChosenLanguage() {
    let json = """
      {"report": {"kind": "USB", "length": 8}, "lowFrequency": {"byte": 1},
       "resendIntervalMilliseconds": 0}
      """
    do {
      _ = try JSONDecoder().decode(ControllerRecordDocument.RumbleTemplate.self, from: Data(json.utf8))
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
}
