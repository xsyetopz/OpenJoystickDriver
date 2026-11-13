import AppKit
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct ActivityLogSeverityTests {
  private func entry(_ stream: ApplicationServiceLogStream, _ text: String) -> ActivityLogEntry {
    ActivityLogEntry(id: 0, stream: stream, text: text)
  }

  @Test
  func standardOutputIsInfoWithTheDefaultLabelColor() {
    let severity = entry(.standardOutput, "Service started").severity
    #expect(severity == .info)
    #expect(severity.tone == nil)
    #expect(severity.symbolName == nil)
  }

  @Test
  func libraryRecordWarningIsAWarningInOrange() {
    let severity = entry(.standardError, "[Library] The record text cannot be shown: x").severity
    #expect(severity == .warning)
    #expect(severity.tone == .attention)
    #expect(severity.tone?.color == .systemOrange)
    #expect(severity.symbolName == "exclamationmark.triangle.fill")
  }

  @Test
  func failedLinesAreErrorsInRedWithTheirOwnSymbol() {
    for text in ["Error: no device", "[Service] Failed to start", "fatal: stop"] {
      let severity = entry(.standardError, text).severity
      #expect(severity == .error)
      #expect(severity.tone == .failure)
      #expect(severity.tone?.color == .systemRed)
      #expect(severity.symbolName == "xmark.octagon.fill")
    }
  }

  @Test
  func iconAndColorComeFromTheSameSeverity() {
    #expect(ActivityLogSeverity.warning.tone != ActivityLogSeverity.error.tone)
    #expect(ActivityLogSeverity.warning.symbolName != ActivityLogSeverity.error.symbolName)
  }
}
