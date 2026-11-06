import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// The Swift manifest decoder and `mod-package.schema.json` must accept and reject the same
/// manifests.
struct ModPackageManifestSchemaTests {
  /// A valid manifest with `changes` applied.
  ///
  /// A nil value removes the key.
  private static func manifest(_ changes: [String: Any?]) -> [String: Any] {
    var document: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ModPackageManifest.kind,
      "name": "arcade-pack",
      "version": "1.0.0", "author": "Tester", "requires": ["minimum": "0.6.0"],
      "controllers": ["1234-abcd.json"],
    ]
    for (key, value) in changes { document[key] = value }
    return document
  }

  private static func accepted() -> [[String: Any]] {
    let unit = "1234-abcd-U-abcdefghijklmnop.json"
    return [
      manifest([:]),
      manifest(["version": "1.0.0-rc.1", "requires": ["minimum": "0.6.0", "below": "1.0.0"]]),
      manifest(["controllers": nil, "profiles": ["My-profile.json"]]),
      manifest(["controllers": nil, "virtualDevices": ["1234-abcd.json", unit]]),
      manifest(["profiles": ["a.json"], "virtualDevices": ["ffff-0000.json"]]),
      manifest([
        "controllers": nil,
        "patches": ["1234-abcd.patch.json", "model-1234-abcd.patch.json", "all.patch.json"],
      ]),
    ]
  }

  private static func rejected() -> [[String: Any]] {
    let unit = "1234-abcd-U-abcdefghijklmnop.json"
    return [
      manifest(["controllers": [String]()]),
      manifest(["controllers": nil, "profiles": [String]()]),
      manifest(["controllers": nil]),
      manifest(["version": "1.0.0+build.5"]),
      manifest(["version": "v1.0.0"]),
      manifest(["version": "01.0.0"]),
      manifest(["requires": ["minimum": "1.0.0+x"]]),
      manifest(["requires": ["minimum": "1.0.0", "below": "2"]]),
      manifest(["requires": [String: String]()]),
      manifest(["controllers": ["Profile.json"]]),
      manifest(["controllers": ["1234-ABCD.json"]]),
      manifest(["controllers": [unit]]),
      manifest(["controllers": nil, "virtualDevices": ["1234-abcd-U-short.json"]]),
      manifest(["controllers": nil, "virtualDevices": ["x.json"]]),
      manifest(["controllers": nil, "profiles": [".hidden.json"]]),
      manifest(["controllers": ["1234-abcd.json", "1234-abcd.json"]]),
      manifest(["name": "Bad"]),
      manifest(["name": "a--b"]),
      manifest(["name": ""]),
      manifest(["author": ""]),
      manifest(["extra": 1]),
      manifest(["records": ["1234-abcd.json"]]),
      manifest(["personas": ["1234-abcd.json"]]),
      manifest(["controllers": nil, "records": ["1234-abcd.json"]]),
      manifest(["controllers": nil, "personas": ["1234-abcd.json"]]),
      manifest(["controllers": ["1234-abcd.patch.json"]]),
      manifest(["controllers": ["all.patch.json"]]),
      manifest(["controllers": nil, "patches": ["1234-abcd.json"]]),
      manifest(["controllers": nil, "patches": [String]()]),
      manifest(["apiVersion": nil]),
      manifest(["apiVersion": "unsupported.example/v9"]),
      manifest(["kind": nil]),
      manifest(["kind": "Controller"]),
      manifest(["$schema": "https://example.com/mod-package.schema.json"]),
    ]
  }

  private func swiftAccepts(_ document: [String: Any]) throws -> Bool {
    let data = try JSONSerialization.data(withJSONObject: document)
    return (try? ModPackageManifest.parse(data)) != nil
  }

  private func schemaAccepts(_ document: [String: Any]) throws -> Bool {
    let data = try JSONSerialization.data(withJSONObject: document)
    let text = try #require(String(bytes: data, encoding: .utf8))
    return try JSONSchemaFiles.issues(in: text, against: "mod-package.schema.json").isEmpty
  }

  @Test
  func theSchemaAndTheDecoderAcceptTheSameManifests() throws {
    for document in Self.accepted() {
      #expect(try schemaAccepts(document), "schema: \(document)")
      #expect(try swiftAccepts(document), "swift: \(document)")
    }
  }

  @Test
  func theSchemaAndTheDecoderRejectTheSameManifests() throws {
    for document in Self.rejected() {
      #expect(try !schemaAccepts(document), "schema: \(document)")
      #expect(try !swiftAccepts(document), "swift: \(document)")
    }
  }
}
