import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

/// `Resources/Schemas/profile.schema.json` accepts what the strict decoder accepts.
struct ProfileSchemaTests {
  /// Uses every kind of source, destination, physical output, and mapping.
  static let richDocument = #"""
    {
      "apiVersion": "openjoystickdriver/v1alpha3",
      "kind": "Profile",
      "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D5E",
      "name": "Everything",
      "device": {"vendorID": 1356, "productID": 3302, "unit": "U-AbCd_123-xyzW09q"},
      "applicationScope": {"type": "Application",
        "appIDs": ["com.example.game", "com.example.other"]},
      "outputPolicy": {"virtualGamepad": "Mapped", "physicalInput": "Exclusive"},
      "physicalColor": {"red": 255, "green": 32, "blue": 0},
      "motionTuning": {
        "space": "World", "lean": {"thresholdDegrees": 20, "hysteresisDegrees": 5},
        "steering": {
          "output": "LeftStickX", "fullScaleDegrees": 45, "deadzoneDegrees": 2,
          "responseExponent": 1.5, "inverted": false
        }
      },
      "gyroOutput": {
        "mode": "Mouse", "activationMode": "WhileHeld",
        "activationSource": {"type": "Button", "button": "RightPaddle2"},
        "trackball": {"source": {"type": "TouchContact", "surface": "Primary"}, "axes": "Yaw"}
      },
      "stickMappings": [
        {
          "source": "Right", "mode": "Flick", "flickThreshold": 0.8, "flickHysteresis": 0.2,
          "tuning": {"innerDeadzone": 0.1, "outerDeadzone": 0.05, "invertY": true}
        }
      ],
      "triggerMappings": [
        {"source": "Left", "mode": "PreferFull", "softThreshold": 0.2, "fullThreshold": 0.9}
      ],
      "touchMappings": [
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D60", "surface": "Primary", "mode": "Pointer",
          "deadzone": 0.05, "pointerSensitivity": 800, "stickRadius": 0.4
        }
      ],
      "bindings": [
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D61",
          "remark": "Jump when pressed",
          "source": {"type": "Button", "button": "South"},
          "destination": {"type": "Keyboard", "key": "Space", "modifiers": ["Shift", "Meta"]},
          "longHold": {
            "durationMs": 500, "destination": {"type": "MouseButton", "button": "Right"}
          },
          "additionalActions": [
            {
              "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D62",
              "destination": {
                "type": "Physical",
                "physical": {"type": "Rumble", "motor": "LowFrequency", "intensity": 0.5}
              }
            }
          ]
        },
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D63",
          "source": {"type": "Axis", "axis": "LeftStickX"},
          "destination": {"type": "GamepadAxis", "axis": "RightStickX"},
          "axisTuning": {
            "deadzone": 0.1, "gain": 2, "inverted": true, "responseCurve": "EaseIn",
            "digitalActivationThreshold": 0.5
          }
        },
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D64",
          "source": {"type": "AxisDirection", "axis": "RightStickY", "direction": "Negative"},
          "destination": {"type": "Keyboard", "key": "ArrowUp", "modifiers": []},
          "axisTuning": {
            "deadzone": 0.2, "gain": 1, "inverted": false, "responseCurve": "Linear",
            "digitalActivationThreshold": 0.6
          }
        },
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D70",
          "source": {"type": "Axis", "axis": "RightStickX"},
          "destination": {"type": "MouseMovement", "axis": "X"},
          "axisTuning": {
            "deadzone": 0.2, "gain": 1, "inverted": false, "responseCurve": "Linear",
            "digitalActivationThreshold": 0.6
          }
        },
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D74",
          "source": {"type": "Axis", "axis": "PointerX"},
          "destination": {"type": "MouseMovement", "axis": "X"},
          "axisTuning": {
            "deadzone": 0.1, "gain": 1, "inverted": false, "responseCurve": "Linear",
            "digitalActivationThreshold": 0.6
          }
        },
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D71",
          "source": {"type": "Axis", "axis": "RightTrigger"},
          "destination": {"type": "Scroll", "axis": "Y"},
          "axisTuning": {
            "deadzone": 0.2, "gain": 1, "inverted": false, "responseCurve": "Linear",
            "digitalActivationThreshold": 0.6
          }
        },
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D72",
          "source": {"type": "Button", "button": "North"},
          "destination": {"type": "MidiNote", "channel": 1, "note": 60, "velocity": 100}
        },
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D73",
          "source": {"type": "Axis", "axis": "LeftTrigger"},
          "destination": {"type": "MidiControlChange", "channel": 16, "controller": 127},
          "axisTuning": {
            "deadzone": 0, "gain": 1, "inverted": false, "responseCurve": "Linear",
            "digitalActivationThreshold": 0.6
          }
        },
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D65",
          "source": {"type": "TriggerStage", "trigger": "Left", "stage": "Full"},
          "destination": {"type": "MouseButton", "button": "Middle"}
        },
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D66",
          "source": {"type": "MotionLean", "direction": "Left"},
          "destination": {"type": "GamepadDpad", "direction": "DpadLeft"}
        },
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D67",
          "source": {
            "type": "TouchGrid", "surface": "Primary",
            "columns": 2, "rows": 1, "column": 1, "row": 0
          },
          "destination": {
            "type": "Physical", "physical": {"type": "Color", "red": 0, "green": 0, "blue": 255}
          },
          "behavior": "TapOnPress"
        },
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D68",
          "source": {
            "type": "TouchSwipe", "surface": "Primary", "direction": "Up", "minimumDistance": 0.3
          },
          "destination": {
            "type": "Physical", "physical": {"type": "PlayerIndicator", "indicator": 2}
          },
          "behavior": "TapOnPress"
        },
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D69",
          "source": {"type": "Dpad", "direction": "DpadUp"},
          "destination": {
            "type": "Physical", "physical": {"type": "Brightness", "intensity": 0.25}
          },
          "behavior": "TapOnPress"
        },
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D6A",
          "source": {"type": "Button", "button": "East"},
          "destination": {
            "type": "Physical",
            "physical": {
              "type": "AdaptiveTrigger", "trigger": "Right",
              "effect": {"kind": "Resistance", "startPosition": 0.3, "strength": 0.7}
            }
          },
          "multiTap": [{
            "count": 2, "windowMs": 250,
            "destination": {"type": "GamepadButton", "button": "North"}
          }]
        }
      ],
      "chords": [
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D6B",
          "sources": [{"type": "Button", "button": "Back"}, {"type": "Button", "button": "Start"}],
          "destination": {"type": "GamepadButton", "button": "Guide"},
          "mode": "Simultaneous", "windowMs": 40
        }
      ],
      "sequences": [
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D6C",
          "sources": [
            {"type": "Dpad", "direction": "DpadDown"}, {"type": "Dpad", "direction": "DpadRight"}
          ],
          "destination": {"type": "Keyboard", "key": "F5", "modifiers": []},
          "windowMs": 600
        }
      ],
      "layers": [
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D6D", "name": "Menus",
          "activationMode": "Toggle", "activator": {"type": "Button", "button": "LeftPaddle1"},
          "bindings": [
            {
              "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D6E",
              "source": {"type": "Button", "button": "West"},
              "destination": {"type": "Keyboard", "key": "Escape", "modifiers": []},
              "turbo": {"repeatRateHz": 10, "dutyCycle": 0.5}
            }
          ],
          "chords": [], "sequences": []
        }
      ]
    }
    """#

  @Test
  func aRichProfileIsAcceptedByTheDecoderAndTheSchema() throws {
    let profile = try RemappingProfileFileStore.load(
      from: PropertyListFixture.data(json: Self.richDocument)
    )
    #expect(try CLIOutputSchema.profileIssues(inJSON: Self.richDocument).isEmpty)
    let encoded = try RemappingProfileFileStore.encodedPlist(profile)
    #expect(try CLIOutputSchema.profileIssues(in: encoded).isEmpty)
  }

  @Test(arguments: [
    ("unknown key", #""name": "Everything""#, #""name": "Everything", "unexpected": true"#),
    ("deadzone out of range", #""deadzone": 0.1, "gain""#, #""deadzone": 0.96, "gain""#),
    ("unknown curve", #""EaseIn""#, #""quadratic""#),
    (
      "pointer as a gamepad axis", #""GamepadAxis", "axis": "RightStickX""#,
      #""GamepadAxis", "axis": "PointerX""#
    ),
    (
      "unknown D-pad direction", #"{"type": "Dpad", "direction": "DpadUp"}"#,
      #"{"type": "Dpad", "direction": "notAName"}"#
    ),
    (
      "unknown destination D-pad direction", #""GamepadDpad", "direction": "DpadLeft""#,
      #""GamepadDpad", "direction": "notAName""#
    ),
    ("unknown gyro mode", #""mode": "Mouse""#, #""mode": "notAName""#),
    (
      "unknown gyro activation", #""activationMode": "WhileHeld""#, #""activationMode": "notAName""#
    ),
    ("unknown gyro axes", #""axes": "Yaw""#, #""axes": "notAName""#),
    ("unknown stick mode", #""mode": "Flick""#, #""mode": "notAName""#),
    ("unknown touch mode", #""mode": "Pointer""#, #""mode": "notAName""#),
    ("unknown axis direction", #""direction": "Negative""#, #""direction": "notAName""#),
    ("unknown keyboard key", #""key": "ArrowUp""#, #""key": "notAName""#),
    (
      "unknown keyboard modifier", #""modifiers": ["Shift", "Meta"]"#, #""modifiers": ["notAName"]"#
    ),
    ("bad app ID", #""com.example.game""#, #""not an app""#),
    ("unknown button", #""button": "South""#, #""button": "a""#),
    ("malformed unit ID", #""U-AbCd_123-xyzW09q""#, #""U-AbCd+123""#),
    ("MIDI channel 0", #""channel": 1, "note": 60"#, #""channel": 0, "note": 60"#),
    ("MIDI channel 17", #""channel": 16, "controller""#, #""channel": 17, "controller""#),
    ("MIDI note 128", #""note": 60"#, #""note": 128"#),
    ("MIDI velocity 0", #""velocity": 100"#, #""velocity": 0"#),
    (
      "axis in a chord", #"{"type": "Button", "button": "Back"}"#,
      #"{"type": "Axis", "axis": "LeftTrigger"}"#
    ),
    (
      "profile name over 80 characters", #""name": "Everything""#,
      "\"name\": \"" + String(repeating: "a", count: 81) + "\""
    ),
    (
      "profile name with a control character", #""name": "Everything""#,
      #""name": "Every\u007fthing""#
    ),
    ("profile name with a space at the end", #""name": "Everything""#, #""name": "Everything ""#),
    (
      "layer name over 40 characters", #""name": "Menus""#,
      "\"name\": \"" + String(repeating: "a", count: 41) + "\""
    ),
    ("layer name with a control character", #""name": "Menus""#, #""name": "Me\u007fnus""#),
    (
      "gyro activation source with the Always mode", #""activationMode": "WhileHeld""#,
      #""activationMode": "Always""#
    ),
    (
      "Off adaptive trigger effect with a strength",
      #""kind": "Resistance", "startPosition": 0.3, "strength": 0.7"#,
      #""kind": "Off", "startPosition": 0, "strength": 0.7"#
    ),
  ])
  func aBrokenProfileIsRejectedByTheDecoderAndTheSchema(
    problem: String,
    original: String,
    replacement: String
  ) throws {
    try Self.expectRejection(problem, original, replacement)
  }

  @Test(arguments: [
    ("empty binding remark", #""remark": """#),
    (
      "binding remark over 200 characters",
      "\"remark\": \"" + String(repeating: "a", count: 201) + "\""
    ),
    ("binding remark with a control character", #""remark": "Jump\u007f""#),
    ("binding remark with a space at the end", #""remark": "Jump ""#),
    ("binding remark that is not text", #""remark": 5"#),
  ])
  func aBrokenBindingRemarkIsRejectedByTheDecoderAndTheSchema(
    problem: String,
    replacement: String
  ) throws {
    try Self.expectRejection(problem, #""remark": "Jump when pressed""#, replacement)
  }

  private static func expectRejection(
    _ problem: String,
    _ original: String,
    _ replacement: String
  ) throws {
    #expect(richDocument.contains(original), "\(problem)")
    let broken = richDocument.replacingOccurrences(of: original, with: replacement)
    do {
      _ = try RemappingProfileFileStore.load(from: PropertyListFixture.data(json: broken))
      Issue.record("\(problem): the profile loads")
    } catch {
      #expect(RemappingProfileFileStore.problemCode(error) == .invalidProfile, "\(problem)")
    }
    #expect(try !CLIOutputSchema.profileIssues(inJSON: broken).isEmpty, "\(problem)")
  }

  /// Rules between fields, which the schema cannot state: the decoder refuses the profile and the
  /// schema accepts it. `wiki/Profile-File-Reference.md` lists them.
  @Test(arguments: [
    ("lean hysteresis above threshold", #""hysteresisDegrees": 5"#, #""hysteresisDegrees": 25"#),
    ("steering deadzone above full scale", #""deadzoneDegrees": 2"#, #""deadzoneDegrees": 50"#),
    (
      "flick hysteresis above threshold", #""flickThreshold": 0.8, "flickHysteresis": 0.2"#,
      #""flickThreshold": 0.3, "flickHysteresis": 0.4"#
    ),
    (
      "stick deadzones fill the travel", #""innerDeadzone": 0.1, "outerDeadzone": 0.05"#,
      #""innerDeadzone": 0.9, "outerDeadzone": 0.5"#
    ),
    ("soft threshold above full", #""softThreshold": 0.2"#, #""softThreshold": 0.95"#),
    ("grid column outside the grid", #""column": 1, "row": 0"#, #""column": 2, "row": 0"#),
    (
      "pulse duration without the Pulse behavior", #""multiTap": [{"#,
      #""pulseDurationMs": 200, "multiTap": [{"#
    ),
  ])
  func aRuleAcrossFieldsIsRefusedByTheDecoderOnly(
    problem: String,
    original: String,
    replacement: String
  ) throws {
    #expect(Self.richDocument.contains(original), "\(problem)")
    let broken = Self.richDocument.replacingOccurrences(of: original, with: replacement)
    do {
      _ = try RemappingProfileFileStore.load(from: PropertyListFixture.data(json: broken))
      Issue.record("\(problem): the profile loads")
    } catch {
      #expect(RemappingProfileFileStore.problemCode(error) == .invalidProfile, "\(problem)")
    }
    #expect(try CLIOutputSchema.profileIssues(inJSON: broken).isEmpty, "\(problem)")
  }

  @Test
  func schemaEnumsMatchTheSwiftCases() throws {
    let pairs: [(String, [String])] = [
      ("button", Self.raw(Control.self)),
      ("axis", Self.raw(RemappingAxis.self)),
      ("touchSurface", Self.raw(RemappingTouchSurface.self)),
      ("triggerSide", Self.raw(RemappingTriggerSource.self)),
      ("stickSide", Self.raw(RemappingStickSource.self)),
      ("axisOutput", Self.raw(RemappingMotionSteeringOutput.self)),
      ("axisTuning/properties/responseCurve", Self.raw(RemappingResponseCurve.self)),
      ("binding/properties/behavior", Self.raw(RemappingBindingBehavior.self)),
      ("chord/properties/mode", Self.raw(RemappingChordMode.self)),
      ("motionTuning/properties/space", Self.raw(RemappingMotionSpace.self)),
      ("gyroTrackball/properties/axes", Self.raw(RemappingGyroTrackballAxes.self)),
      ("gyroOutput/properties/mode", Self.raw(RemappingGyroOutputMode.self)),
      ("gyroOutput/properties/activationMode", Self.raw(RemappingGyroActivationMode.self)),
      ("stickMapping/properties/mode", Self.raw(RemappingStickMode.self)),
      ("stickMapping/properties/scrollAxis", Self.raw(RemappingStickScrollAxis.self)),
      (
        "stickMapping/properties/rotationDirection",
        Self.raw(RemappingStickRotationDirection.self)
      ),
      ("stickMapping/properties/steeringOutput", Self.raw(RemappingStickSteeringOutput.self)),
      ("triggerMapping/properties/mode", Self.raw(RemappingDualStageTriggerMode.self)),
      ("touchMapping/properties/mode", Self.raw(RemappingTouchMode.self)),
      ("adaptiveTriggerEffect/properties/kind", Self.raw(PhysicalAdaptiveTriggerEffectKind.self)),
    ]
    let definitions = try #require(
      try CLIOutputSchema.document(named: CLIOutputSchema.profileFileName)["$defs"]
        as? [String: Any]
    )
    for (pointer, cases) in pairs {
      var node: Any = definitions
      for key in pointer.split(separator: "/") {
        node = try #require((node as? [String: Any])?[String(key)], "\(pointer)")
      }
      if let reference = (node as? [String: Any])?["$ref"] as? String,
        reference.hasPrefix("vocabulary.schema.json#/$defs/")
      {
        let name = String(reference.dropFirst("vocabulary.schema.json#/$defs/".count))
        let vocabulary = try #require(
          try JSONSchemaFiles.document(named: "vocabulary.schema.json")["$defs"]
            as? [String: Any]
        )
        node = try #require(vocabulary[name], "\(reference)")
      }
      let values = try #require((node as? [String: Any])?["enum"] as? [String], "\(pointer)")
      #expect(values == cases, "\(pointer)")
    }
  }

  @Test
  func vocabularyAndKeyboardEnumsMatchTheSwiftCases() throws {
    let vocabulary = try #require(
      try JSONSchemaFiles.document(named: "vocabulary.schema.json")["$defs"] as? [String: Any]
    )
    let dpad = try #require((vocabulary["dpadControl"] as? [String: Any])?["enum"] as? [String])
    #expect(dpad == Self.raw(RemappingDpadDirection.self))
    let gamepadAxes = try #require(
      (vocabulary["gamepadAxis"] as? [String: Any])?["enum"] as? [String]
    )
    #expect(gamepadAxes == RemappingAxis.allCases.filter { !$0.isPointer }.map(\.rawValue))
    let definitions = try #require(
      try CLIOutputSchema.document(named: CLIOutputSchema.profileFileName)["$defs"]
        as? [String: Any]
    )
    let destinations = try #require(
      (definitions["destination"] as? [String: Any])?["oneOf"] as? [[String: Any]]
    )
    let keyboard = try #require(
      destinations.first {
        (($0["properties"] as? [String: Any])?["type"] as? [String: Any])?["const"] as? String
          == "Keyboard"
      }?["properties"] as? [String: Any]
    )
    let key = try #require((keyboard["key"] as? [String: Any])?["enum"] as? [String])
    #expect(key == Self.raw(RemappingKeyboardKey.self))
    let modifiers = try #require(
      ((keyboard["modifiers"] as? [String: Any])?["items"] as? [String: Any])?["enum"]
        as? [String]
    )
    #expect(modifiers.sorted() == Self.raw(RemappingKeyModifier.self).sorted())
    let root = try CLIOutputSchema.document(named: CLIOutputSchema.profileFileName)
    let selection = try #require(
      ((((root["properties"] as? [String: Any])?["joyConPair"] as? [String: Any])?["properties"]
        as? [String: Any])?["gyroSelection"] as? [String: Any])?["enum"] as? [String]
    )
    #expect(selection == Self.raw(RemappingJoyConGyroSelection.self))
  }

  private static func raw<T: CaseIterable & RawRepresentable>(_: T.Type) -> [String]
  where T.RawValue == String { T.allCases.map(\.rawValue) }
}
