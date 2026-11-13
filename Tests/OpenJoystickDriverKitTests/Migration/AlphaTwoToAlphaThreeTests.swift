import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct AlphaTwoToAlphaThreeTests {
  private func convert(_ text: String, _ kind: DocumentKind) throws -> OrderedJSON {
    try AlphaTwoToAlphaThree.convert(OrderedJSON.parse(Data(text.utf8)), kind: kind)
  }

  @Test
  func patchNullBecomesRemoveEntry() throws {
    let converted = try convert(MigrationFixtures.nullPatch, .controllerPatch)
    #expect(converted["apiVersion"]?.string == OpenJoystickDriverAPI.version)
    #expect(converted["remove"] == .array([.string("usb"), .string("tuning.replyTimeoutMs")]))
    #expect(converted["patch"]?.formatted().contains("null") == false)
    #expect(converted["patch"]?["tuning"]?["frameQueueCapacity"] == .number("8"))
    #expect(converted["patch"]?["usb"] == nil)
  }

  @Test
  func patchOfNullsOnlyHasNoPatch() throws {
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
  func patchWithModesRemovesRecordModesFirst() throws {
    let text = MigrationFixtures.document(
      MigrationFixtures.alphaTwo,
      "ControllerPatch",
      #""selector": {"all": true}, "patch": {"modes": [{"id": "default"}], "#
        + #""tuning": {"replyTimeoutMs": null}}"#
    )
    let converted = try convert(text, .controllerPatch)
    #expect(converted["remove"] == .array([.string("tuning.replyTimeoutMs"), .string("modes")]))
    #expect(converted["patch"]?["modes"] != nil)
  }

  @Test
  func notesAndRationaleDropped() throws {
    let text = MigrationFixtures.document(
      MigrationFixtures.alphaTwo,
      "Controller",
      #""vendorID": 1, "productID": 2, "notes": "x", "#
        + #""modes": [{"id": "default", "rationale": "y"}]"#
    )
    let converted = try convert(text, .controller)
    #expect(converted["notes"] == nil)
    #expect(converted["modes"]?.formatted().contains("rationale") == false)
  }

  @Test
  func nullOutsidePatchDropped() throws {
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
  func settingsDocumentGainsAdvancedInterfaceLevel() throws {
    let text = MigrationFixtures.document(
      MigrationFixtures.alphaTwo,
      "Settings",
      #""showInDock": true"#
    )
    let converted = try convert(text, .settings)
    #expect(converted["interfaceLevel"] == .string("Advanced"))
    #expect(converted["showInDock"] == .bool(true))
  }

  @Test
  func otherKindsGainNoInterfaceLevel() throws {
    let converted = try convert(MigrationFixtures.nullPatch, .controllerPatch)
    #expect(converted["interfaceLevel"] == nil)
  }

  @Test
  func nullInListHasNoMapping() {
    let text = MigrationFixtures.document(
      MigrationFixtures.alphaTwo,
      "Settings",
      #""list": [1, null]"#
    )
    #expect(throws: DocumentMigrationProblem.self) { try convert(text, .settings) }
  }

  @Test
  func profileAppIDBecomesListOfOne() throws {
    let text = MigrationFixtures.document(
      MigrationFixtures.alphaTwo,
      "Profile",
      #""applicationScope": {"type": "Application", "appID": "com.example.game"}"#
    )
    let converted = try convert(text, .profile)
    let scope = try #require(converted["applicationScope"])
    #expect(scope["appID"] == nil)
    #expect(scope["appIDs"] == .array([.string("com.example.game")]))
    #expect(scope["type"]?.string == "Application")
  }

  @Test
  func globalProfileScopeUnchanged() throws {
    let text = MigrationFixtures.document(
      MigrationFixtures.alphaTwo,
      "Profile",
      #""applicationScope": {"type": "Global"}"#
    )
    let converted = try convert(text, .profile)
    #expect(
      converted["applicationScope"] == .object([.init(key: "type", value: .string("Global"))])
    )
  }

  @Test
  func appIDNotStringHasNoMapping() {
    let text = MigrationFixtures.document(
      MigrationFixtures.alphaTwo,
      "Profile",
      #""applicationScope": {"type": "Application", "appID": 3}"#
    )
    #expect(throws: DocumentMigrationProblem.self) { try convert(text, .profile) }
  }

  @Test
  func recordIdleMovesToDefaultMode() throws {
    let text = MigrationFixtures.document(
      MigrationFixtures.alphaTwo,
      "Controller",
      #""vendorID": 1, "productID": 2, "idle": true, "#
        + #""modes": [{"id": "default", "protocol": {"family": "HIDDescriptor"}}]"#
    )
    let converted = try convert(text, .controller)
    #expect(converted["idle"] == nil)
    #expect(converted["modes"]?.array?.first?["idle"]?.string == "NoControllerLinked")
  }

  @Test
  func recordWithoutIdleKeepsItsModes() throws {
    let text = MigrationFixtures.document(
      MigrationFixtures.alphaTwo,
      "Controller",
      #""vendorID": 1, "productID": 2, "#
        + #""modes": [{"id": "default", "protocol": {"family": "HIDDescriptor"}}]"#
    )
    #expect(try convert(text, .controller)["modes"]?.array?.first?["idle"] == nil)
  }

  @Test
  func patchIdleBecomesMergedDefaultMode() throws {
    let text = MigrationFixtures.document(
      MigrationFixtures.alphaTwo,
      "ControllerPatch",
      #""selector": {"vendorID": 1, "productID": 2}, "patch": {"idle": true}"#
    )
    let patch = try #require(try convert(text, .controllerPatch)["patch"])
    #expect(patch["idle"] == nil)
    let modes = try #require(patch["modes"]?.array)
    #expect(modes.count == 1)
    #expect(modes[0]["id"]?.string == "default")
    #expect(modes[0]["idle"]?.string == "NoControllerLinked")
  }

  @Test
  func patchIdleJoinsDefaultModePatchSets() throws {
    let text = MigrationFixtures.document(
      MigrationFixtures.alphaTwo,
      "ControllerPatch",
      #""selector": {"vendorID": 1, "productID": 2}, "patch": {"idle": true, "#
        + #""modes": [{"id": "default", "protocol": {"family": "HIDDescriptor"}}]}"#
    )
    let patch = try #require(try convert(text, .controllerPatch)["patch"])
    let modes = try #require(patch["modes"]?.array)
    #expect(modes.count == 1)
    #expect(modes[0]["protocol"] != nil)
    #expect(modes[0]["idle"]?.string == "NoControllerLinked")
  }

  @Test
  func patchRemovesIdleHasNoMapping() {
    let text = MigrationFixtures.document(
      MigrationFixtures.alphaTwo,
      "ControllerPatch",
      #""selector": {"vendorID": 1, "productID": 2}, "patch": {"idle": null}"#
    )
    #expect(throws: DocumentMigrationProblem.self) { try convert(text, .controllerPatch) }
  }

  @Test
  func chainStartsAtVersionOneAndEndsAtVersionThree() {
    let steps = DocumentMigrationStep.all.filter { $0.kind == DocumentKind.profile.rawValue }
    #expect(steps.map(\.from) == [MigrationFixtures.alphaOne, MigrationFixtures.alphaTwo])
    #expect(steps.last?.to == OpenJoystickDriverAPI.version)
  }
}
