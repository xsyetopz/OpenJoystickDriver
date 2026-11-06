import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite("Build identity")
struct BuildIdentityTests {
  @Test
  func jsonUsesTypedLowerCamelFields() throws {
    let identity = BuildIdentity(
      semanticVersion: "0.5.0-beta.4",
      appBundleVersion: "1.4.89",
      sourceCommit: String(repeating: "a", count: 40),
      sourceState: .clean
    )
    let object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(identity)) as? [String: Any]
    )

    #expect(object["semanticVersion"] as? String == "0.5.0-beta.4")
    #expect(object["appBundleVersion"] as? String == "1.4.89")
    #expect(object["sourceState"] as? String == "Clean")
  }

  @Test
  func displayCarriesProvenanceAsSemVerBuildMetadata() throws {
    let identity = BuildIdentity(
      semanticVersion: "0.5.0-beta.4",
      appBundleVersion: "1.4.89",
      sourceCommit: "0123456789abcdef0123456789abcdef01234567",
      sourceState: .dirty
    )

    #expect(identity.display == "0.5.0-beta.4+build.1.4.89.sha.0123456789ab.dirty")
    let parsed = try #require(SemanticVersion(identity.display))
    #expect(parsed == SemanticVersion("0.5.0-beta.4"))
  }

  @Test
  func aboutLineAddsTheBundleVersionAsTheAboutPanelShowsIt() {
    let identity = BuildIdentity(
      semanticVersion: "0.6.0-alpha.1",
      appBundleVersion: "1.19.57",
      sourceCommit: "558c65ce01964e6d031769b23eabba1cf14cbc61",
      sourceState: .clean
    )

    #expect(identity.aboutLine == "0.6.0-alpha.1+build.1.19.57.sha.558c65ce0196 (1.19.57)")
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
      inputRead: .granted,
      inputInject: .granted,
      connectedDevices: []
    )
    let object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(status)) as? [String: Any]
    )

    let encodedIdentity = try #require(object["buildIdentity"] as? [String: Any])
    #expect(encodedIdentity["sourceCommit"] as? String == identity.sourceCommit)
  }

  @Test
  func currentReadsTheAppBundleThroughTheInstalledLink() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let contents = root.appendingPathComponent("OpenJoystickDriver.app/Contents")
    let executable = contents.appendingPathComponent("MacOS/OpenJoystickDriver")
    try FileManager.default.createDirectory(
      at: executable.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data().write(to: executable)
    let info: [String: Any] = [
      "CFBundleExecutable": "OpenJoystickDriver",
      "CFBundleShortVersionString": "0.5.0-beta.5",
      "CFBundleVersion": "1.5.1",
      "OJDSourceCommit": String(repeating: "c", count: 40),
      "OJDSourceState": "Clean",
    ]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
      .write(to: contents.appendingPathComponent("Info.plist"))
    let link = root.appendingPathComponent("bin/ojd")
    try FileManager.default.createDirectory(
      at: link.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: executable)

    let identity = BuildIdentity.current(executableURL: link)

    #expect(identity.semanticVersion == "0.5.0-beta.5")
    #expect(identity.appBundleVersion == "1.5.1")
    #expect(identity.sourceState == .clean)
  }

  @Test
  func aMissingSourceStateIsUnknownAndAnInvalidOneIsRefused() throws {
    #expect(try BuildIdentity(info: [:]).sourceState == .unknown)
    #expect(try BuildIdentity(info: ["OJDSourceState": "Dirty"]).sourceState == .dirty)
    for name in ["clean", "dirty", "unknown", "notAWord"] {
      #expect(throws: BuildIdentityError.invalidSourceState(name)) {
        try BuildIdentity(info: ["OJDSourceState": name])
      }
    }
    #expect(throws: BuildIdentityError.invalidSourceState("1")) {
      try BuildIdentity(info: ["OJDSourceState": 1])
    }
  }
}
