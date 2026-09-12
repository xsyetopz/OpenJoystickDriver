import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct CommandValueParserTests {
  @Test func parsesControllerSourceAndSystemTarget() throws {
    #expect(try RemappingCommandValueParser.source("button:south") == .button(.south))
    #expect(
      try RemappingCommandValueParser.destination("key:a:mods=command,shift")
        == .keyboard(key: .a, modifiers: [.command, .shift])
    )
  }

  @Test func parsesTypedTouchSources() throws {
    #expect(
      try RemappingCommandValueParser.source("touch:left:contact") == .touchContact(.left)
    )
    #expect(
      try RemappingCommandValueParser.source("touch:right:grid:3:2:1:0")
        == .touchGrid(
          RemappingTouchGridSource(surface: .right, columns: 3, rows: 2, column: 1, row: 0)
        )
    )
    #expect(
      try RemappingCommandValueParser.source("touch:primary:swipe:up:0.25")
        == .touchSwipe(
          RemappingTouchSwipeSource(
            surface: .primary, direction: .up, minimumDistance: 0.25
          )
        )
    )
    #expect(throws: RemappingCommandValueError.invalidSource("touch:left:grid:2:2:0")) {
      try RemappingCommandValueParser.source("touch:left:grid:2:2:0")
    }
  }

  @Test func parsesTriggerStagesAndMotionLeanSources() throws {
    #expect(
      try RemappingCommandValueParser.source("trigger:left:soft") == .triggerStage(.left, .soft)
    )
    #expect(
      try RemappingCommandValueParser.source("trigger:right:full") == .triggerStage(.right, .full)
    )
    #expect(
      try RemappingCommandValueParser.source("motion:lean:left") == .motionLean(.left)
    )
    #expect(throws: RemappingCommandValueError.invalidSource("trigger:left:middle")) {
      try RemappingCommandValueParser.source("trigger:left:middle")
    }
  }

  @Test func parsesBoundedPhysicalOutputTargets() throws {
    #expect(
      try RemappingCommandValueParser.destination("physical:rumble:leftMain:0.5")
        == .physical(.rumble(motor: .leftMain, intensity: 0.5))
    )
    #expect(
      try RemappingCommandValueParser.destination("physical:adaptive:right:resistance:0.4:0.8")
        == .physical(
          .adaptiveTrigger(
            .right,
            PhysicalAdaptiveTriggerEffect(
              kind: .resistance, startPosition: 0.4, strength: 0.8
            )
          )
        )
    )
    #expect(
      throws: RemappingCommandValueError.invalidDestination("physical:brightness:1.1")
    ) {
      try RemappingCommandValueParser.destination("physical:brightness:1.1")
    }
  }

  @Test func profileFileStoreValidatesAndRoundTrips() throws {
    let profile = RemappingProfile(
      name: "Portable",
      device: RemappingDeviceScope(vendorID: 1118, productID: 654),
      applicationScope: .global,
      bindings: [
        RemappingBinding(
          source: .button(.south),
          destination: .keyboard(key: .space, modifiers: [])
        )
      ]
    )
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("json")
    defer { try? FileManager.default.removeItem(at: url) }

    try RemappingProfileFileStore.write(profile, to: url)
    #expect(try RemappingProfileFileStore.load(from: url) == profile)
    #expect(try RemappingProfileFileStore.encodedJSON(profile).contains("Portable"))

    var object = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    )
    object["schema_version"] = 2
    object["bindings"] = "must not be decoded"
    try JSONSerialization.data(withJSONObject: object).write(to: url)
    #expect(throws: RemappingValidationError.unsupportedSchemaVersion(2)) {
      try RemappingProfileFileStore.load(from: url)
    }
  }
}
