import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

struct ExtensionProbeTests {
  @Test func distinguishesActiveInactiveAndAbsentRegistration() {
    let identifier = ExtensionProbe.bundleIdentifier
    let active = result(output: "* * ABC \(identifier) [activated enabled]")
    let inactive = result(output: "* * ABC \(identifier) [activated waiting for user]")
    let absent = result(output: "1 extension(s)")

    #expect(ExtensionProbe.registration(from: active) == .active(active.output))
    #expect(ExtensionProbe.registration(from: inactive) == .inactive(inactive.output))
    #expect(ExtensionProbe.registration(from: absent) == .absent)
  }

  @Test func queryFailuresNeverBecomeAbsence() {
    let timeout = result(output: "", timedOut: true)
    let failed = result(output: "permission denied", terminationStatus: 1)
    let truncated = result(output: "unrelated", outputWasTruncated: true)

    guard case .unavailable = ExtensionProbe.registration(from: timeout) else {
      Issue.record("A timeout must be unavailable")
      return
    }
    guard case .unavailable = ExtensionProbe.registration(from: failed) else {
      Issue.record("A command failure must be unavailable")
      return
    }
    guard case .unavailable = ExtensionProbe.registration(from: truncated) else {
      Issue.record("Truncated evidence must be unavailable")
      return
    }
  }

  @Test func missingEmbeddedBundleRemainsSeparateFromOSRegistration() throws {
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }

    #expect(ExtensionProbe.bundleState(in: temporary) == .missing)
  }

  private func result(
    output: String,
    terminationStatus: Int32 = 0,
    timedOut: Bool = false,
    outputWasTruncated: Bool = false
  ) -> BoundedProcessResult {
    BoundedProcessResult(
      terminationStatus: terminationStatus,
      output: output,
      timedOut: timedOut,
      outputWasTruncated: outputWasTruncated
    )
  }
}
