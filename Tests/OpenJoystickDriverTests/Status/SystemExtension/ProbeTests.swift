import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

struct ProbeTests {
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

  @Test func parsesInstalledShortAndBuildVersions() {
    let output = "* * \(ExtensionProbe.bundleIdentifier) (0.5.0-beta.2/0.5.0b2) [activated enabled]"
    let facts = ExtensionProbe.installedFacts(from: output)

    #expect(
      facts
        == ExtensionVersionFacts(
          bundleIdentifier: ExtensionProbe.bundleIdentifier,
          shortVersion: "0.5.0-beta.2",
          buildVersion: "0.5.0b2"
        )
    )
    #expect(
      ExtensionProbe.installedFacts(
        from: "* * \(ExtensionProbe.bundleIdentifier) (0.5.0-beta.1/0.5.0b1)"
      )?.buildVersion == "0.5.0b1"
    )
    #expect(
      ExtensionProbe.installedFacts(
        from: "* * \(ExtensionProbe.bundleIdentifier) (0.5.0-beta.3/0.5.0b3)"
      )?.shortVersion == "0.5.0-beta.3"
    )
    for build in ["13", "500001", "500002"] {
      #expect(
        ExtensionProbe.installedFacts(
          from: "* * \(ExtensionProbe.bundleIdentifier) (0.5.0-beta.1/\(build))"
        )?.buildVersion == build
      )
    }
    #expect(
      ExtensionProbe.installedFacts(from: "malformed (ExtensionProbe.bundleIdentifier)") == nil
    )
    #expect(
      ExtensionProbe.installedFacts(
        from: "* * \(ExtensionProbe.bundleIdentifier) (0.5.0-beta.3 0.5.0b3)"
      ) == nil
    )
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
