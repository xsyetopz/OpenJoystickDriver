import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite("Build identity")
struct BuildIdentityTests {
  @Test
  func displayUsesShortCommitAndMarksOnlyDirtySources() {
    let commit = "abcdef1234567890abcdef1234567890abcdef12"
    let clean = BuildIdentity(
      semanticVersion: "0.5.0-beta.4",
      appBundleVersion: "1.4.89",
      sourceCommit: commit,
      sourceState: .clean
    )
    let dirty = BuildIdentity(
      semanticVersion: clean.semanticVersion,
      appBundleVersion: clean.appBundleVersion,
      sourceCommit: commit,
      sourceState: .dirty
    )

    #expect(clean.display == "0.5.0-beta.4 (build 1.4.89, abcdef123456)")
    #expect(dirty.display == "0.5.0-beta.4 (build 1.4.89, abcdef123456-dirty)")
  }

  @Test
  func JSONUsesTypedSnakeCaseFields() throws {
    let identity = BuildIdentity(
      semanticVersion: "0.5.0-beta.4",
      appBundleVersion: "1.4.89",
      sourceCommit: String(repeating: "a", count: 40),
      sourceState: .clean
    )
    let object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(identity)) as? [String: Any]
    )

    #expect(object["semantic_version"] as? String == "0.5.0-beta.4")
    #expect(object["app_bundle_version"] as? String == "1.4.89")
    #expect(object["source_state"] as? String == "clean")
  }

  @Test
  func statusJSONExposesBuildIdentityAtTheTopLevel() throws {
    let identity = BuildIdentity(
      semanticVersion: "0.5.0-beta.4",
      appBundleVersion: "1.4.89",
      sourceCommit: String(repeating: "b", count: 40),
      sourceState: .clean
    )
    let status = ApplicationServiceStatusPayload(
      buildIdentity: identity,
      inputMonitoring: "granted",
      accessibility: "granted",
      connectedDevices: []
    )
    let object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(status)) as? [String: Any]
    )

    let encodedIdentity = try #require(object["build_identity"] as? [String: Any])
    #expect(encodedIdentity["source_commit"] as? String == identity.sourceCommit)
  }
}
