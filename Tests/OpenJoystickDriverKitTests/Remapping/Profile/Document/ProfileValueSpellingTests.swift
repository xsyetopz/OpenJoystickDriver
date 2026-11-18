import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ProfileValueSpellingTests {
  @Test
  func bindingBehaviorRejectsSnakeCaseSpelling() {
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(
        RemappingBindingBehavior.self,
        from: Data(#""tap_on_press""#.utf8)
      )
    }
    #expect(RemappingBindingBehavior(rawValue: "tap_on_press") == nil)
  }

  @Test
  func responseCurveRejectsSnakeCaseSpelling() {
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(RemappingResponseCurve.self, from: Data(#""ease_in""#.utf8))
    }
  }

  @Test
  func rumbleMotorRejectsNamesBeforeActuatorNames() {
    for name in ["leftMain", "rightMain", "leftTrigger", "left_main"] {
      #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(PhysicalRumbleMotor.self, from: Data(#""\#(name)""#.utf8))
      }
    }
    #expect(PhysicalRumbleMotor(rawValue: "LowFrequency") == .lowFrequency)
  }

  @Test
  func sourceTypeInLowerCaseIsRejected() {
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(
        RemappingSource.self,
        from: Data(#"{"type":"touch_contact","surface":"Primary"}"#.utf8)
      )
    }
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(
        RemappingSource.self,
        from: Data(#"{"type":"TouchContact","surface":"primary"}"#.utf8)
      )
    }
  }

  @Test
  func commandLineSpellingsSelectCaseWhoseKebabNameTheyAre() {
    #expect(
      CommandLineName.value(of: "tap-on-press", in: RemappingBindingBehavior.self) == .tapOnPress
    )
    #expect(CommandLineName.value(of: "tap_on_press", in: RemappingBindingBehavior.self) == nil)
    #expect(CommandLineName.value(of: "ease-in", in: RemappingResponseCurve.self) == .easeIn)
    #expect(
      CommandLineName.value(of: "low-frequency", in: PhysicalRumbleMotor.self) == .lowFrequency
    )
    #expect(CommandLineName.value(of: "leftMain", in: PhysicalRumbleMotor.self) == nil)
  }

  @Test
  func everyCommandLineEnumHasDistinctSpellings() {
    #expect(CommandLineName.collisions(in: RemappingBindingBehavior.self).isEmpty)
    #expect(CommandLineName.collisions(in: RemappingResponseCurve.self).isEmpty)
    #expect(CommandLineName.collisions(in: RemappingVirtualGamepadPolicy.self).isEmpty)
    #expect(CommandLineName.collisions(in: RemappingPhysicalInputPolicy.self).isEmpty)
    #expect(CommandLineName.collisions(in: RemappingDualStageTriggerMode.self).isEmpty)
    #expect(CommandLineName.collisions(in: PhysicalRumbleMotor.self).isEmpty)
  }

  @Test
  func commandValueParserTakesKebabWordsAndRefusesDocumentSpelling() throws {
    #expect(
      try RemappingCommandValueParser.source("trigger:left:soft") == .triggerStage(.left, .soft)
    )
    #expect(throws: RemappingCommandValueError.self) {
      try RemappingCommandValueParser.source("trigger:Left:Soft")
    }
    #expect(
      try RemappingCommandValueParser.destination("physical:rumble:low-frequency:0.5")
        == .physical(.rumble(motor: .lowFrequency, intensity: 0.5))
    )
    #expect(throws: RemappingCommandValueError.self) {
      try RemappingCommandValueParser.destination("physical:rumble:leftMain:0.5")
    }
  }

  /// Decodes `spelling` as a `Kind`, or reports that it names no case.
  private static func decodes<Kind: Decodable>(_: Kind.Type, _ spelling: String) -> Bool {
    (try? JSONDecoder().decode(Kind.self, from: Data("\"\(spelling)\"".utf8))) != nil
  }

  /// Each kind takes its UpperCamelCase value and refuses the `replaced` spelling.
  @Test
  func everyRenamedKindRefusesItsEarlierSpelling() {
    typealias Case = (kind: String, current: String, replaced: String, accepts: (String) -> Bool)
    let cases: [Case] = [
      (
        "behavior", "TapOnRelease", "tap_on_release",
        { Self.decodes(RemappingBindingBehavior.self, $0) }
      ),
      (
        "response curve", "SmoothStep", "smooth_step",
        { Self.decodes(RemappingResponseCurve.self, $0) }
      ),
      (
        "rumble motor", "HighFrequency", "rightMain", { Self.decodes(PhysicalRumbleMotor.self, $0) }
      ),
      (
        "trigger mode", "ResponsivePreferFullCombined", "responsive_prefer_full_combined",
        { Self.decodes(RemappingDualStageTriggerMode.self, $0) }
      ),
      ("chord mode", "Simultaneous", "simultaneous", { Self.decodes(RemappingChordMode.self, $0) }),
      ("layer activation", "Toggle", "toggle", { Self.decodes(RemappingLayerActivation.self, $0) }),
      ("motion space", "World", "world", { Self.decodes(RemappingMotionSpace.self, $0) }),
      (
        "virtual gamepad policy", "Passthrough", "passthrough",
        { Self.decodes(RemappingVirtualGamepadPolicy.self, $0) }
      ),
      (
        "physical input policy", "Exclusive", "exclusive",
        { Self.decodes(RemappingPhysicalInputPolicy.self, $0) }
      ),
      (
        "adaptive trigger kind", "Resistance", "resistance",
        { Self.decodes(PhysicalAdaptiveTriggerEffectKind.self, $0) }
      ),
      ("adaptive trigger", "Right", "right", { Self.decodes(PhysicalAdaptiveTrigger.self, $0) }),
      ("touch surface", "Primary", "primary", { Self.decodes(RemappingTouchSurface.self, $0) }),
      ("swipe direction", "Down", "down", { Self.decodes(RemappingTouchSwipeDirection.self, $0) }),
      ("stage", "Soft", "soft", { Self.decodes(RemappingTriggerStage.self, $0) }),
      ("lean direction", "Left", "left", { Self.decodes(RemappingMotionLeanDirection.self, $0) }),
      ("mouse button", "Forward", "forward", { Self.decodes(RemappingMouseButton.self, $0) }),
      ("pointer axis", "X", "x", { Self.decodes(RemappingPointerAxis.self, $0) }),
      ("stick source", "Right", "right", { Self.decodes(RemappingStickSource.self, $0) }),
      (
        "scroll axis", "Horizontal", "horizontal",
        { Self.decodes(RemappingStickScrollAxis.self, $0) }
      ),
      (
        "rotation direction", "Clockwise", "clockwise",
        { Self.decodes(RemappingStickRotationDirection.self, $0) }
      ),
    ]
    for entry in cases {
      #expect(entry.accepts(entry.current), "\(entry.kind) takes \(entry.current)")
      #expect(!entry.accepts(entry.replaced), "\(entry.kind) refuses \(entry.replaced)")
    }
  }

  @Test
  func scopeTypesTakeUpperCamelCaseOnly() throws {
    let decoder = JSONDecoder()
    #expect(
      try decoder.decode(RemappingApplicationScope.self, from: Data(#"{"type":"Global"}"#.utf8))
        == .global
    )
    #expect(
      try decoder.decode(
        RemappingApplicationScope.self,
        from: Data(
          #"{"type":"Application","appIDs":["com.example.game","com.example.other"]}"#.utf8
        )
      ) == .application(appIDs: ["com.example.game", "com.example.other"])
    )
    for type in ["global", "application"] {
      #expect(throws: DecodingError.self) {
        try decoder.decode(
          RemappingApplicationScope.self,
          from: Data(#"{"type":"\#(type)","appIDs":["com.example.game"]}"#.utf8)
        )
      }
    }
  }

  /// Each `type` discriminator, with the members its kind needs.
  private static let sourceTypes: [(type: String, members: String)] = [
    ("Button", #""button":"South""#), ("Dpad", #""direction":"DpadUp""#),
    ("Axis", #""axis":"LeftStickX""#),
    ("AxisDirection", #""axis":"LeftStickX","direction":"Negative""#),
    ("TriggerStage", #""trigger":"Left","stage":"Soft""#), ("MotionLean", #""direction":"Left""#),
    ("TouchContact", #""surface":"Primary""#),
    ("TouchGrid", #""surface":"Primary","columns":2,"rows":2,"column":0,"row":1"#),
    ("TouchSwipe", #""surface":"Left","direction":"Up","minimumDistance":0.25"#),
  ]

  private static let destinationTypes: [(type: String, members: String)] = [
    ("Keyboard", #""key":"Space","modifiers":[]"#), ("GamepadButton", #""button":"South""#),
    ("GamepadDpad", #""direction":"DpadUp""#), ("GamepadAxis", #""axis":"RightStickX""#),
    ("MouseButton", #""button":"Left""#), ("MouseMovement", #""axis":"X""#),
    ("Scroll", #""axis":"Y""#),
    ("Physical", #""physical":{"type":"Brightness","intensity":0.5}"#),
  ]

  private static func replacedSpelling(of type: String) -> String {
    CommandLineName.kebab(type).replacingOccurrences(of: "-", with: "_")
  }

  @Test(arguments: 0..<9)
  func sourceTypesTakeUpperCamelCaseOnly(index: Int) throws {
    let entry = Self.sourceTypes[index]
    let decoder = JSONDecoder()
    _ = try decoder.decode(
      RemappingSource.self,
      from: Data(#"{"type":"\#(entry.type)",\#(entry.members)}"#.utf8)
    )
    #expect(throws: DecodingError.self) {
      try decoder.decode(
        RemappingSource.self,
        from: Data(
          #"{"type":"\#(Self.replacedSpelling(of: entry.type))",\#(entry.members)}"#.utf8
        )
      )
    }
  }

  @Test(arguments: 0..<8)
  func destinationTypesTakeUpperCamelCaseOnly(index: Int) throws {
    let entry = Self.destinationTypes[index]
    let decoder = JSONDecoder()
    _ = try decoder.decode(
      RemappingDestination.self,
      from: Data(#"{"type":"\#(entry.type)",\#(entry.members)}"#.utf8)
    )
    #expect(throws: DecodingError.self) {
      try decoder.decode(
        RemappingDestination.self,
        from: Data(
          #"{"type":"\#(Self.replacedSpelling(of: entry.type))",\#(entry.members)}"#.utf8
        )
      )
    }
  }

  @Test
  func physicalOutputTypesTakeUpperCamelCaseOnly() throws {
    let members: [(String, String)] = [
      ("Rumble", #""motor":"LowFrequency","intensity":0.5"#),
      ("PlayerIndicator", #""indicator":1"#),
      ("Color", #""red":1,"green":2,"blue":3"#),
      ("Brightness", #""intensity":0.5"#),
      (
        "AdaptiveTrigger",
        #""trigger":"Left","effect":{"kind":"Off","startPosition":0,"strength":0}"#
      ),
    ]
    for (type, fields) in members {
      _ = try JSONDecoder().decode(
        RemappingPhysicalOutput.self,
        from: Data(#"{"type":"\#(type)",\#(fields)}"#.utf8)
      )
      #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(
          RemappingPhysicalOutput.self,
          from: Data(#"{"type":"\#(Self.replacedSpelling(of: type))",\#(fields)}"#.utf8)
        )
      }
    }
  }
}
