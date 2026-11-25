import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct DocumentVersionTests {
  private func parse(_ text: String) throws -> OrderedJSON {
    try OrderedJSON.parse(Data(text.utf8))
  }

  @Test
  func currentIsTheNewestVersionAndTheOneTheAPISpeaks() {
    #expect(DocumentVersion.allCases.last == DocumentVersion.current)
    #expect(OpenJoystickDriverAPI.version == DocumentVersion.current.rawValue)
    #expect(OpenJoystickDriverAPI.schemaBase.hasSuffix("/schemas/\(DocumentVersion.current.name)/"))
  }

  @Test
  func everyVersionIsNamedUnderThePrefix() {
    for version in DocumentVersion.allCases {
      #expect(version.rawValue == DocumentVersion.prefix + version.name)
    }
  }

  @Test
  func additiveVersionOnlyRewritesTheAPIVersion() throws {
    let text = MigrationFixtures.document(
      MigrationFixtures.alphaThree,
      "Settings",
      #""showInDock": true, "interfaceLevel": "Advanced""#
    )
    let converted = try DocumentVersion.v1alpha3.migrate(parse(text), kind: .settings)
    let expected = MigrationFixtures.document(
      DocumentVersion.current.rawValue,
      "Settings",
      #""showInDock": true, "interfaceLevel": "Advanced""#
    )
    #expect(converted == (try parse(expected)))
  }

  @Test
  func oldestVersionPassesThroughEveryUpgradeToCurrent() throws {
    let converted = try DocumentVersion.v1alpha1.migrate(
      parse(MigrationFixtures.profile),
      kind: .profile
    )
    #expect(converted["apiVersion"]?.string == DocumentVersion.current.rawValue)
    #expect(converted.formatted().contains("multiTap"))
    #expect(!converted.formatted().contains("doubleTap"))
  }

  @Test
  func currentVersionIsLeftAsItIs() throws {
    let text = MigrationFixtures.document(
      DocumentVersion.current.rawValue,
      "Settings",
      #""showInDock": true"#
    )
    let document = try parse(text)
    #expect(try DocumentVersion.current.migrate(document, kind: .settings) == document)
  }
}
