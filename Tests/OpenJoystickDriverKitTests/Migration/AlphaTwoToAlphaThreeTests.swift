import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct AlphaTwoToAlphaThreeTests {
  private func convert(_ text: String, _ kind: DocumentKind) throws -> OrderedJSON {
    try AlphaTwoToAlphaThree.convert(OrderedJSON.parse(Data(text.utf8)), kind: kind)
  }

  @Test
  func aPatchNullBecomesARemoveEntry() throws {
    let converted = try convert(MigrationFixtures.nullPatch, .controllerPatch)
    #expect(converted["apiVersion"]?.string == OpenJoystickDriverAPI.version)
    #expect(converted["remove"] == .array([.string("usb"), .string("tuning.replyTimeoutMs")]))
    #expect(converted["patch"]?.formatted().contains("null") == false)
    #expect(converted["patch"]?["tuning"]?["frameQueueCapacity"] == .number("8"))
    #expect(converted["patch"]?["usb"] == nil)
  }

  @Test
  func aPatchOfNullsOnlyHasNoPatch() throws {
    let text = MigrationFixtures.document(
      MigrationFixtures.alphaTwo,
      "ControllerPatch",
      #""selector": {"all": true}, "patch": {"tuning": {"replyTimeoutMs": null}}"#
    )
    let converted = try convert(text, .controllerPatch)
    #expect(converted["patch"] == nil)
    #expect(converted["remove"] == .array([.string("tuning.replyTimeoutMs")]))
  }

  @Test
  func aPatchWithModesRemovesTheRecordModesFirst() throws {
    let text = MigrationFixtures.document(
      MigrationFixtures.alphaTwo,
      "ControllerPatch",
      #""selector": {"all": true}, "patch": {"modes": [{"id": "default"}], "tuning": {"replyTimeoutMs": null}}"#
    )
    let converted = try convert(text, .controllerPatch)
    #expect(converted["remove"] == .array([.string("tuning.replyTimeoutMs"), .string("modes")]))
    #expect(converted["patch"]?["modes"] != nil)
  }

  @Test
  func notesAndRationaleAreDropped() throws {
    let text = MigrationFixtures.document(
      MigrationFixtures.alphaTwo,
      "Controller",
      #""vendorID": 1, "productID": 2, "notes": "x", "modes": [{"id": "default", "rationale": "y"}]"#
    )
    let converted = try convert(text, .controller)
    #expect(converted["notes"] == nil)
    #expect(converted["modes"]?.formatted().contains("rationale") == false)
  }

  @Test
  func aNullOutsideAPatchIsDropped() throws {
    let text = MigrationFixtures.document(
      MigrationFixtures.alphaTwo,
      "Settings",
      #""showInDock": true, "lastCheck": null"#
    )
    let converted = try convert(text, .settings)
    #expect(converted["lastCheck"] == nil)
    #expect(converted["showInDock"] == .bool(true))
  }

  @Test
  func aNullInAListHasNoMapping() {
    let text = MigrationFixtures.document(
      MigrationFixtures.alphaTwo,
      "Settings",
      #""list": [1, null]"#
    )
    #expect(throws: DocumentMigrationProblem.self) { try convert(text, .settings) }
  }

  @Test
  func theChainStartsAtVersionOneAndEndsAtVersionThree() throws {
    let steps = DocumentMigrationStep.all.filter { $0.kind == DocumentKind.profile.rawValue }
    #expect(steps.map(\.from) == [MigrationFixtures.alphaOne, MigrationFixtures.alphaTwo])
    #expect(steps.last?.to == OpenJoystickDriverAPI.version)
  }
}
