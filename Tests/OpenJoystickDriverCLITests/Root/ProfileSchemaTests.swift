import Foundation
import OpenJoystickDriverKit
import Testing

/// `Resources/Schemas/profile.schema.json` accepts what the strict decoder accepts.
struct ProfileSchemaTests {
  /// Uses every kind of source, destination, physical output, and mapping.
  static let richDocument = #"""
    {
      "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D5E",
      "name": "Everything",
      "device": {"vendorID": 1356, "productID": 3302},
      "applicationScope": {"type": "application", "bundleIdentifier": "com.example.game"},
      "outputPolicy": {"virtualGamepad": "mapped", "physicalInput": "exclusive"},
      "physicalColor": {"red": 255, "green": 32, "blue": 0},
      "motionTuning": {
        "space": "world", "lean": {"thresholdDegrees": 20, "hysteresisDegrees": 5},
        "steering": {
          "output": "left_stick_x", "fullScaleDegrees": 45, "deadzoneDegrees": 2,
          "responseExponent": 1.5, "inverted": false
        }
      },
      "gyroOutput": {
        "mode": "mouse", "activationMode": "while_held",
        "activationSource": {"type": "button", "button": "right_grip"},
        "trackball": {"source": {"type": "touch_contact", "surface": "primary"}, "axes": "yaw"}
      },
      "stickMappings": [
        {
          "source": "right", "mode": "flick", "flickThreshold": 0.8, "flickHysteresis": 0.2,
          "tuning": {"innerDeadzone": 0.1, "outerDeadzone": 0.05, "invertY": true}
        }
      ],
      "triggerMappings": [
        {"source": "left", "mode": "prefer_full", "softThreshold": 0.2, "fullThreshold": 0.9}
      ],
      "touchMappings": [
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D60", "surface": "primary", "mode": "pointer",
          "deadzone": 0.05, "pointerSensitivity": 800, "stickRadius": 0.4
        }
      ],
      "bindings": [
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D61",
          "source": {"type": "button", "button": "south"},
          "destination": {"type": "keyboard", "key": "space", "modifiers": ["shift", "command"]},
          "longHold": {
            "durationMs": 500, "destination": {"type": "mouse_button", "button": "right"}
          },
          "additionalActions": [
            {
              "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D62",
              "destination": {
                "type": "physical",
                "physical": {"type": "rumble", "motor": "leftMain", "intensity": 0.5}
              }
            }
          ]
        },
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D63",
          "source": {"type": "axis", "axis": "left_stick_x"},
          "destination": {"type": "gamepad_axis", "axis": "right_stick_x"},
          "axisTuning": {
            "deadzone": 0.1, "gain": 2, "inverted": true, "responseCurve": "ease_in",
            "digitalActivationThreshold": 0.5
          }
        },
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D64",
          "source": {"type": "axis_direction", "axis": "right_stick_y", "direction": "negative"},
          "destination": {"type": "keyboard", "key": "arrow_up", "modifiers": []},
          "axisTuning": {
            "deadzone": 0.2, "gain": 1, "inverted": false, "responseCurve": "linear",
            "digitalActivationThreshold": 0.6
          }
        },
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D70",
          "source": {"type": "axis", "axis": "right_stick_x"},
          "destination": {"type": "mouse_movement", "axis": "x"},
          "axisTuning": {
            "deadzone": 0.2, "gain": 1, "inverted": false, "responseCurve": "linear",
            "digitalActivationThreshold": 0.6
          }
        },
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D71",
          "source": {"type": "axis", "axis": "right_trigger"},
          "destination": {"type": "scroll", "axis": "y"},
          "axisTuning": {
            "deadzone": 0.2, "gain": 1, "inverted": false, "responseCurve": "linear",
            "digitalActivationThreshold": 0.6
          }
        },
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D65",
          "source": {"type": "trigger_stage", "trigger": "left", "stage": "full"},
          "destination": {"type": "mouse_button", "button": "middle"}
        },
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D66",
          "source": {"type": "motion_lean", "direction": "left"},
          "destination": {"type": "gamepad_dpad", "direction": "left"}
        },
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D67",
          "source": {
            "type": "touch_grid", "surface": "primary",
            "columns": 2, "rows": 1, "column": 1, "row": 0
          },
          "destination": {
            "type": "physical", "physical": {"type": "color", "red": 0, "green": 0, "blue": 255}
          },
          "behavior": "tap_on_press"
        },
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D68",
          "source": {
            "type": "touch_swipe", "surface": "primary", "direction": "up", "minimumDistance": 0.3
          },
          "destination": {
            "type": "physical", "physical": {"type": "player_indicator", "indicator": 2}
          },
          "behavior": "tap_on_press"
        },
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D69",
          "source": {"type": "dpad", "direction": "up"},
          "destination": {
            "type": "physical", "physical": {"type": "brightness", "intensity": 0.25}
          },
          "behavior": "tap_on_press"
        },
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D6A",
          "source": {"type": "button", "button": "east"},
          "destination": {
            "type": "physical",
            "physical": {
              "type": "adaptive_trigger", "trigger": "right",
              "effect": {"kind": "resistance", "startPosition": 0.3, "strength": 0.7}
            }
          },
          "doubleTap": {
            "windowMs": 250, "destination": {"type": "gamepad_button", "button": "north"}
          }
        }
      ],
      "chords": [
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D6B",
          "sources": [{"type": "button", "button": "back"}, {"type": "button", "button": "start"}],
          "destination": {"type": "gamepad_button", "button": "guide"},
          "mode": "simultaneous", "windowMs": 40
        }
      ],
      "sequences": [
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D6C",
          "sources": [
            {"type": "dpad", "direction": "down"}, {"type": "dpad", "direction": "right"}
          ],
          "destination": {"type": "keyboard", "key": "f5", "modifiers": []},
          "windowMs": 600
        }
      ],
      "layers": [
        {
          "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D6D", "name": "Menus",
          "activationMode": "toggle", "activator": {"type": "button", "button": "left_paddle"},
          "bindings": [
            {
              "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D6E",
              "source": {"type": "button", "button": "west"},
              "destination": {"type": "keyboard", "key": "escape", "modifiers": []},
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
    let profile = try RemappingProfileFileStore.load(from: Data(Self.richDocument.utf8))
    #expect(try CLIOutputSchema.profileIssues(in: Self.richDocument).isEmpty)
    let encoded = try RemappingProfileFileStore.encodedJSON(profile)
    #expect(try CLIOutputSchema.profileIssues(in: encoded).isEmpty)
  }

  @Test(arguments: [
    ("unknown key", #""name": "Everything""#, #""name": "Everything", "unexpected": true"#),
    ("deadzone out of range", #""deadzone": 0.1, "gain""#, #""deadzone": 0.96, "gain""#),
    ("unknown curve", #""ease_in""#, #""quadratic""#),
    ("bad bundle ID", #""com.example.game""#, #""not an app""#),
    ("unknown button", #""button": "south""#, #""button": "a""#),
    (
      "axis in a chord", #"{"type": "button", "button": "back"}"#,
      #"{"type": "axis", "axis": "left_trigger"}"#
    ),
  ])
  func aBrokenProfileIsRejectedByTheDecoderAndTheSchema(
    problem: String,
    original: String,
    replacement: String
  ) throws {
    #expect(Self.richDocument.contains(original), "\(problem)")
    let broken = Self.richDocument.replacingOccurrences(of: original, with: replacement)
    #expect(throws: (any Error).self, "\(problem)") {
      try RemappingProfileFileStore.load(from: Data(broken.utf8))
    }
    #expect(try !CLIOutputSchema.profileIssues(in: broken).isEmpty, "\(problem)")
  }

  @Test
  func schemaEnumsMatchTheSwiftCases() throws {
    let pairs: [(String, [String])] = [
      ("button", Self.raw(RemappingButton.self)),
      ("axis", Self.raw(RemappingAxis.self)),
      ("dpadDirection", Self.raw(RemappingDpadDirection.self)),
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
      let values = try #require((node as? [String: Any])?["enum"] as? [String], "\(pointer)")
      #expect(values == cases, "\(pointer)")
    }
  }

  private static func raw<T: CaseIterable & RawRepresentable>(_: T.Type) -> [String]
  where T.RawValue == String { T.allCases.map(\.rawValue) }
}
