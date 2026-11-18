import Testing

@testable import OpenJoystickDriverKit

@Suite
struct RecordStartupWriteMessageTests {
  private static func message(_ build: () throws -> Void) -> String? {
    do {
      try build()
      return nil
    } catch {
      return ControllerRecordSet.problemDescription(
        error,
        document: "record",
        localization: Localization(preferredLanguages: ["en-US"]),
        file: "046d-c21d.plist"
      )
    }
  }

  @Test
  func wrongByteCountNamesCountReportTakes() {
    let report = ControllerTemplateReport(kind: .output, reportID: 1, length: 7)
    #expect(
      Self.message { _ = try RecordStartupWrite(report: report, bytes: [0, 1, 2]) }
        == "046d-c21d.plist, session.startup[].bytes: A startup write must list 6 bytes, every "
        + "byte after the report ID. Fix: Give bytes 6 bytes."
    )
  }

  @Test
  func inputReportNamesFileKeyPathRuleAndFix() {
    let report = ControllerTemplateReport(kind: .input, reportID: 1, length: 7)
    #expect(
      Self.message { _ = try RecordStartupWrite(report: report, bytes: []) }
        == "046d-c21d.plist, session.startup[].report: A startup write cannot send an input "
        + "report. Fix: Set report to an output or feature report."
    )
  }

  @Test
  func usbTimeoutOutsideItsRangeNamesRange() {
    #expect(
      Self.message { _ = try USBStartupWrite(bytes: [1], timeoutMilliseconds: 0) }
        == "046d-c21d.plist, session.startup[].timeoutMilliseconds: A USB startup timeout must "
        + "be 1...60000 ms. Fix: Set timeoutMilliseconds to 1...60000, or leave it out."
    )
  }
}
