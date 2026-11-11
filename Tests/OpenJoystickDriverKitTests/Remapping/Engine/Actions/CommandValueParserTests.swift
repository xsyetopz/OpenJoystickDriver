import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct CommandValueParserTests {
  @Test
  func parsesControllerSourceAndSystemTarget() throws {
    #expect(try RemappingCommandValueParser.source("button:south") == .button(.south))
    #expect(
      try RemappingCommandValueParser.destination("key:key-a:mods=meta,shift")
        == .keyboard(key: .a, modifiers: [.meta, .shift])
    )
  }

  @Test
  func parsesProfileControlTargets() throws {
    let id = UUID()
    #expect(try RemappingCommandValueParser.destination("pause:toggle") == .pause(.toggle))
    #expect(
      try RemappingCommandValueParser.destination("profile:switch:previous")
        == .profileSwitch(.previous)
    )
    #expect(
      try RemappingCommandValueParser.destination("profile:switch:\(id.uuidString)")
        == .profileSwitch(.profile(id))
    )
    let layer = RemappingCommandValueParser.layerTarget("layer:Aim: low:off")
    #expect(layer?.name == "Aim: low")
    #expect(layer?.mode == .off)
    #expect(RemappingCommandValueParser.layerTarget("layer::on") == nil)
    #expect(RemappingCommandValueParser.layerTarget("layer:Aim:maybe") == nil)
    for text in ["pause:maybe", "profile:switch:later", "layer:Aim:on"] {
      #expect(throws: RemappingCommandValueError.invalidDestination(text)) {
        try RemappingCommandValueParser.destination(text)
      }
    }
  }

  @Test
  func parsesTypedTouchSources() throws {
    #expect(try RemappingCommandValueParser.source("touch:left:contact") == .touchContact(.left))
    #expect(
      try RemappingCommandValueParser.source("touch:right:grid:3:2:1:0")
        == .touchGrid(
          RemappingTouchGridSource(surface: .right, columns: 3, rows: 2, column: 1, row: 0)
        )
    )
    #expect(
      try RemappingCommandValueParser.source("touch:primary:swipe:up:0.25")
        == .touchSwipe(
          RemappingTouchSwipeSource(surface: .primary, direction: .up, minimumDistance: 0.25)
        )
    )
    #expect(throws: RemappingCommandValueError.invalidSource("touch:left:grid:2:2:0")) {
      try RemappingCommandValueParser.source("touch:left:grid:2:2:0")
    }
  }

  @Test
  func parsesTriggerStagesAndMotionLeanSources() throws {
    #expect(
      try RemappingCommandValueParser.source("trigger:left:soft") == .triggerStage(.left, .soft)
    )
    #expect(
      try RemappingCommandValueParser.source("trigger:right:full") == .triggerStage(.right, .full)
    )
    #expect(try RemappingCommandValueParser.source("motion:lean:left") == .motionLean(.left))
    #expect(throws: RemappingCommandValueError.invalidSource("trigger:left:middle")) {
      try RemappingCommandValueParser.source("trigger:left:middle")
    }
  }

  @Test
  func parsesMIDITargets() throws {
    #expect(
      try RemappingCommandValueParser.destination("midi-note:1:60")
        == .midiNote(channel: 1, note: 60, velocity: 127)
    )
    #expect(
      try RemappingCommandValueParser.destination("midi-note:16:127:1")
        == .midiNote(channel: 16, note: 127, velocity: 1)
    )
    #expect(
      try RemappingCommandValueParser.destination("midi-cc:3:7")
        == .midiControlChange(channel: 3, controller: 7)
    )
    for raw in [
      "midi-note:0:60", "midi-note:17:60", "midi-note:1:128", "midi-note:1:60:0",
      "midi-note:1:60:128", "midi-note:1", "midi-note:1:60:100:1", "midi-note:x:60",
      "midi-cc:0:1", "midi-cc:1:128", "midi-cc:1", "midi-cc:1:2:3",
    ] {
      #expect(throws: RemappingCommandValueError.invalidDestination(raw), "\(raw)") {
        try RemappingCommandValueParser.destination(raw)
      }
    }
  }

  @Test
  func parsesBoundedPhysicalOutputTargets() throws {
    #expect(
      try RemappingCommandValueParser.destination("physical:rumble:low-frequency:0.5")
        == .physical(.rumble(motor: .lowFrequency, intensity: 0.5))
    )
    #expect(
      try RemappingCommandValueParser.destination("physical:adaptive:right:resistance:0.4:0.8")
        == .physical(
          .adaptiveTrigger(
            .right,
            PhysicalAdaptiveTriggerEffect(kind: .resistance, startPosition: 0.4, strength: 0.8)
          )
        )
    )
    #expect(throws: RemappingCommandValueError.invalidDestination("physical:brightness:1.1")) {
      try RemappingCommandValueParser.destination("physical:brightness:1.1")
    }
  }

  @Test
  func profileFileStoreValidatesAndRoundTrips() throws {
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
    #expect(try RemappingProfileFileStore.encodedPlist(profile).contains("Portable"))

    var object = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    )
    object["schemaVersion"] = 2
    try JSONSerialization.data(withJSONObject: object).write(to: url)
    #expect(throws: DecodingError.self) { try RemappingProfileFileStore.load(from: url) }
  }
}
