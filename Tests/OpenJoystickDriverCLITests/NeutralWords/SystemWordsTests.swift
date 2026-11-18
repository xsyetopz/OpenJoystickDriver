import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI
@testable import OpenJoystickDriverKit

/// The OS-neutral words of the command line and the support report.
struct SystemWordsTests {
  @Test
  func diagnoseHelpListsOutputFlag() async {
    let result = await CLIRun.run(["diagnose", "--help"])

    #expect(result.code == 0)
    #expect(result.standardOutput.contains("--output"))
  }

  private func reportDocument() throws -> [String: Any] {
    let audit = SystemGamepadSupportAuditor.audit(
      snapshot: SystemGamepadCatalogSnapshot(
        source: .downloadedMobileAsset,
        bundleVersions: ["10.5.2"],
        entries: [
          SystemGamepadCatalogEntry(vendorID: 1_234, productID: 5_678, identifiers: ["a.b"])
        ]
      ),
      records: [ControllerModelID(vendorID: 1_234, productID: 5_678)]
    )
    let report = SupportReport(
      generatedAt: Date(timeIntervalSince1970: 0),
      buildIdentity: BuildIdentity(
        semanticVersion: "0.5.0-beta.4",
        appBundleVersion: "1.4.89",
        sourceCommit: String(repeating: "a", count: 40),
        sourceState: .clean
      ),
      osName: "macOS",
      osVersion: "26.0.0",
      architecture: "arm64",
      inputRead: .granted,
      applicationServiceInstalled: true,
      applicationServiceConnected: true,
      applicationServiceHealth: nil,
      systemGamepadAudit: audit,
      status: nil,
      virtualDiagnostics: nil
    )
    let object = try JSONSerialization.jsonObject(with: report.encodedJSON())
    return try #require(object as? [String: Any])
  }

  private func issues(
    in document: [String: Any],
    against reference: String = "report.schema.json"
  ) throws -> [String] {
    try JSONSchemaFiles.Validator().validate(
      document,
      against: ["$ref": reference],
      in: String(reference.prefix { $0 != "#" }),
      at: "$"
    )
  }

  @Test
  func reportPassesSchema() throws {
    let document = try reportDocument()

    #expect(try issues(in: document).isEmpty)
    let system = try #require((document["data"] as? [String: Any])?["system"] as? [String: Any])
    #expect(system["osName"] as? String == "macOS")
    #expect(system["osVersion"] as? String == "26.0.0")
  }

  @Test
  func diagnoseDocumentWithOutputPassesSchema() throws {
    let document: [String: Any] = [
      "apiVersion": "openjoystickdriver/v1alpha3", "kind": "Diagnosis", "checks": [],
      "timings": [], "output": "/tmp/support.json",
    ]

    #expect(try issues(in: document, against: "cli-output.schema.json#/$defs/diagnose").isEmpty)
  }

  @Test
  func unknownFlagIsRefusedAsUsageError() async {
    let unknown = "--x\(UUID().uuidString.prefix(8).lowercased())"
    let result = await CLIRun.run(["diagnose", unknown, "/tmp/support.json"])

    #expect(result.code == CLIExitCode.usage.rawValue)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.contains(unknown))
  }

  @Test
  func unknownFieldInDiagnoseDocumentFailsSchema() throws {
    let unknown = "x\(UUID().uuidString.prefix(8).lowercased())"
    let document: [String: Any] = [
      "apiVersion": "openjoystickdriver/v1alpha3", "kind": "Diagnosis", "checks": [],
      "timings": [], unknown: "/tmp/support.json",
    ]

    let found = try issues(in: document, against: "cli-output.schema.json#/$defs/diagnose")

    #expect(found.contains { $0.contains(unknown) })
  }
}
