import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

struct ProbeTests {
  @Test
  func readsBundleStateAndVersionFromEmbeddedExtension() throws {
    let appURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("ProbeTests-\(UUID().uuidString).app")
    defer { try? FileManager.default.removeItem(at: appURL) }
    #expect(ExtensionProbe.bundleState(in: appURL) == .missing)

    let extensionURL = appURL.appendingPathComponent(
      "Contents/Library/SystemExtensions/\(ExtensionProbe.extensionID).dext"
    )
    try FileManager.default.createDirectory(at: extensionURL, withIntermediateDirectories: true)
    let info: [String: Any] = [
      "CFBundleIdentifier": ExtensionProbe.extensionID,
      "CFBundleShortVersionString": "0.6.0-alpha.1",
      "CFBundleVersion": "1.14.55d1",
      "CFBundlePackageType": "DEXT",
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try data.write(to: extensionURL.appendingPathComponent("Info.plist"))

    #expect(ExtensionProbe.bundleState(in: appURL) == .present)
    #expect(
      ExtensionProbe.embeddedFacts(in: appURL)
        == ExtensionVersionFacts(
          extensionID: ExtensionProbe.extensionID,
          shortVersion: "0.6.0-alpha.1",
          buildVersion: "1.14.55d1"
        )
    )
  }

  @Test
  func distinguishesActiveInactiveAndAbsentRegistration() {
    let identifier = ExtensionProbe.extensionID
    let active = result(output: "* * ABC \(identifier) [activated enabled]")
    let inactive = result(output: "* * ABC \(identifier) [activated waiting for user]")
    let absent = result(output: "1 extension(s)")

    #expect(ExtensionProbe.registration(from: active) == .active(active.output))
    #expect(ExtensionProbe.registration(from: inactive) == .inactive(inactive.output))
    #expect(ExtensionProbe.registration(from: absent) == .absent)
  }

  @Test
  func queryFailuresNeverBecomeAbsence() {
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

  @Test
  func parsesInstalledShortAndBuildVersions() {
    let output = "* * \(ExtensionProbe.extensionID) (0.5.0-beta.2/0.5.0b2) [activated enabled]"
    let facts = ExtensionProbe.installedFacts(from: output)

    #expect(
      facts
        == ExtensionVersionFacts(
          extensionID: ExtensionProbe.extensionID,
          shortVersion: "0.5.0-beta.2",
          buildVersion: "0.5.0b2"
        )
    )
    #expect(
      ExtensionProbe.installedFacts(
        from: "* * \(ExtensionProbe.extensionID) (0.5.0-beta.1/0.5.0b1)"
      )?.buildVersion == "0.5.0b1"
    )
    #expect(
      ExtensionProbe.installedFacts(
        from: "* * \(ExtensionProbe.extensionID) (0.5.0-beta.3/0.5.0b3)"
      )?.shortVersion == "0.5.0-beta.3"
    )
    for short in ["0.5.0-beta.5", "1.0.0-rc.1.2", "1.0.0"] {
      for build in ["1.4.89", "1.4.89d2"] {
        #expect(
          ExtensionProbe.installedFacts(
            from: "* * \(ExtensionProbe.extensionID) (\(short)/\(build))"
          )
            == ExtensionVersionFacts(
              extensionID: ExtensionProbe.extensionID,
              shortVersion: short,
              buildVersion: build
            )
        )
      }
    }
    for build in ["13", "500001", "500002"] {
      #expect(
        ExtensionProbe.installedFacts(
          from: "* * \(ExtensionProbe.extensionID) (0.5.0-beta.1/\(build))"
        )?.buildVersion == build
      )
    }
    #expect(
      ExtensionProbe.installedFacts(from: "malformed (ExtensionProbe.extensionID)") == nil
    )
    #expect(
      ExtensionProbe.installedFacts(
        from: "* * \(ExtensionProbe.extensionID) (0.5.0-beta.3 0.5.0b3)"
      ) == nil
    )
  }

  @Test
  func readsInstalledVersionFromActiveLineWhenUpgradeLeavesOldLine() {
    // Arrange: macOS lists the replaced version until the next restart.
    let identifier = ExtensionProbe.extensionID
    let output = """
      *\t\t9PQP6CDMQT\t\(identifier) (0.6.0-alpha.2/1.25.4)\tXboxUSBDevice\t\
      [terminated waiting to uninstall on reboot]
      *\t*\t9PQP6CDMQT\t\(identifier) (0.6.0-alpha.3/1.30.13)\tXboxUSBDevice\t\
      [activated enabled]
      """

    // Act
    let facts = ExtensionProbe.installedFacts(from: output)

    // Assert
    #expect(
      facts
        == ExtensionVersionFacts(
          extensionID: identifier,
          shortVersion: "0.6.0-alpha.3",
          buildVersion: "1.30.13"
        )
    )
  }

  @Test
  func missingEmbeddedBundleRemainsSeparateFromOSRegistration() throws {
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
