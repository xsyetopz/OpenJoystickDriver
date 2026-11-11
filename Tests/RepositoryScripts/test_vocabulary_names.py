from __future__ import annotations

import copy
import json
import plistlib
import unittest
from typing import Any, cast

from Scripts.Quality import validate_schemas

VERSION = "openjoystickdriver/v1alpha3"
ROOT = validate_schemas.ROOT
SAMPLE_PROFILE = ROOT / "docs" / "sdk" / "sample" / "Profiles" / "sample-pad.plist"
UUID = "3B0F9C52-6E1D-4A8B-9C27-5D4E8F1A0B"
UNKNOWN = "notAName"

# Where a profile names a kind, as a path into the profile below.
PROFILE_KINDS: dict[str, tuple[Any, ...]] = {
    "D-pad source direction": ("bindings", 1, "source", "direction"),
    "D-pad destination direction": ("bindings", 2, "destination", "direction"),
    "axis direction": ("bindings", 3, "source", "direction"),
    "keyboard key": ("bindings", 0, "destination", "key"),
    "keyboard modifier": ("bindings", 0, "destination", "modifiers", 0),
    "gyro mode": ("gyroOutput", "mode"),
    "gyro activation": ("gyroOutput", "activationMode"),
    "gyro axes": ("gyroOutput", "trackball", "axes"),
    "Joy-Con gyro selection": ("joyConPair", "gyroSelection"),
    "stick mode": ("stickMappings", 0, "mode"),
    "touch mode": ("touchMappings", 0, "mode"),
}


def profile() -> dict[str, Any]:
    with SAMPLE_PROFILE.open("rb") as source:
        document = plistlib.load(source)
    document["bindings"] = [
        {
            "id": f"{UUID}02",
            "source": {"type": "Button", "button": "Start"},
            "destination": {
                "type": "Keyboard",
                "key": "KeyJ",
                "modifiers": ["Meta"],
            },
        },
        {
            "id": f"{UUID}03",
            "source": {"type": "Dpad", "direction": "DpadUp"},
            "destination": {"type": "MouseButton", "button": "Left"},
        },
        {
            "id": f"{UUID}04",
            "source": {"type": "Button", "button": "South"},
            "destination": {"type": "GamepadDpad", "direction": "DpadLeft"},
        },
        {
            "id": f"{UUID}05",
            "source": {
                "type": "AxisDirection",
                "axis": "LeftStickX",
                "direction": "Negative",
            },
            "destination": {"type": "GamepadButton", "button": "East"},
        },
    ]
    document["gyroOutput"] = {
        "mode": "Mouse",
        "activationMode": "WhileHeld",
        "activationSource": {"type": "Button", "button": "LeftShoulder"},
        "trackball": {
            "axes": "Yaw",
            "source": {"type": "Button", "button": "RightShoulder"},
        },
    }
    document["joyConPair"] = {"gyroSelection": "Left"}
    document["stickMappings"] = [{"source": "Left", "mode": "FlickOnly"}]
    document["touchMappings"] = [
        {
            "id": f"{UUID}06",
            "surface": "Primary",
            "mode": "LeftStick",
            "deadzone": 0.1,
            "pointerSensitivity": 100,
            "stickRadius": 0.5,
        }
    ]
    return document


def replace(document: dict[str, Any], path: tuple[Any, ...], value: Any) -> None:
    node: Any = document
    for step in path[:-1]:
        node = node[step]
    node[path[-1]] = value


def renamed_kinds_profile() -> dict[str, Any]:
    """A profile that uses every kind the naming rule renamed in profiles."""
    document = profile()
    base = {"type": "Button", "button": "South"}
    tuning = {
        "deadzone": 0.1,
        "gain": 1,
        "inverted": False,
        "responseCurve": "EaseIn",
        "digitalActivationThreshold": 0.5,
    }
    document["outputPolicy"] = {
        "virtualGamepad": "Passthrough",
        "physicalInput": "Exclusive",
    }
    document["motionTuning"] = {"space": "World"}
    document["bindings"] += [
        {
            "id": f"{UUID}10",
            "source": base,
            "destination": {"type": "Keyboard", "key": "Space", "modifiers": []},
            "behavior": "TapOnPress",
        },
        {
            "id": f"{UUID}11",
            "source": {"type": "Axis", "axis": "LeftStickX"},
            "destination": {"type": "GamepadAxis", "axis": "RightStickX"},
            "axisTuning": tuning,
        },
        {
            "id": f"{UUID}12",
            "source": {"type": "TriggerStage", "trigger": "Left", "stage": "Soft"},
            "destination": {
                "type": "Physical",
                "physical": {
                    "type": "Rumble",
                    "motor": "LowFrequency",
                    "intensity": 0.5,
                },
            },
        },
        {
            "id": f"{UUID}13",
            "source": {"type": "MotionLean", "direction": "Left"},
            "destination": {
                "type": "Physical",
                "physical": {
                    "type": "AdaptiveTrigger",
                    "trigger": "Right",
                    "effect": {
                        "kind": "Resistance",
                        "startPosition": 0.2,
                        "strength": 0.5,
                    },
                },
            },
        },
        {
            "id": f"{UUID}14",
            "source": {
                "type": "TouchSwipe",
                "surface": "Left",
                "direction": "Up",
                "minimumDistance": 0.25,
            },
            "destination": {"type": "MouseMovement", "axis": "X"},
        },
        {
            "id": f"{UUID}15",
            "source": {"type": "TouchContact", "surface": "Primary"},
            "destination": {"type": "Scroll", "axis": "Y"},
        },
    ]
    document["triggerMappings"] = [{"source": "Left", "mode": "PreferFull"}]
    document["chords"] = [
        {
            "id": f"{UUID}16",
            "sources": [base, {"type": "Button", "button": "East"}],
            "destination": {"type": "Keyboard", "key": "Space", "modifiers": []},
            "mode": "Modifier",
        }
    ]
    document["layers"] = [
        {
            "id": f"{UUID}17",
            "name": "Layer",
            "activationMode": "Toggle",
            "activator": {"type": "Button", "button": "North"},
            "bindings": [],
            "chords": [],
            "sequences": [],
        }
    ]
    return document


# Where the profile above names a renamed kind, and the spelling that kind had before.
RENAMED_PROFILE_KINDS: dict[str, tuple[tuple[Any, ...], str]] = {
    "application scope type": (("applicationScope", "type"), "global"),
    "virtual gamepad policy": (("outputPolicy", "virtualGamepad"), "passthrough"),
    "physical input policy": (("outputPolicy", "physicalInput"), "exclusive"),
    "motion space": (("motionTuning", "space"), "world"),
    "binding behavior": (("bindings", 4, "behavior"), "tap_on_press"),
    "source type": (("bindings", 5, "source", "type"), "axis"),
    "destination type": (("bindings", 5, "destination", "type"), "gamepad_axis"),
    "response curve": (("bindings", 5, "axisTuning", "responseCurve"), "ease_in"),
    "trigger stage": (("bindings", 6, "source", "stage"), "soft"),
    "rumble motor": (("bindings", 6, "destination", "physical", "motor"), "leftMain"),
    "physical output type": (
        ("bindings", 6, "destination", "physical", "type"),
        "rumble",
    ),
    "lean direction": (("bindings", 7, "source", "direction"), "left"),
    "adaptive trigger side": (
        ("bindings", 7, "destination", "physical", "trigger"),
        "right",
    ),
    "adaptive trigger kind": (
        ("bindings", 7, "destination", "physical", "effect", "kind"),
        "resistance",
    ),
    "swipe direction": (("bindings", 8, "source", "direction"), "up"),
    "touch surface": (("bindings", 9, "source", "surface"), "primary"),
    "mouse movement axis": (("bindings", 8, "destination", "axis"), "x"),
    "scroll axis": (("bindings", 9, "destination", "axis"), "y"),
    "trigger mode": (("triggerMappings", 0, "mode"), "prefer_full"),
    "trigger source": (("triggerMappings", 0, "source"), "left"),
    "chord mode": (("chords", 0, "mode"), "modifier"),
    "layer activation": (("layers", 0, "activationMode"), "toggle"),
    "stick source": (("stickMappings", 0, "source"), "left"),
}


class VocabularyNameTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.documents = validate_schemas.validate_schema_documents()
        cls.registry = validate_schemas.schema_registry(cls.documents)

    def validator(self, name: str) -> Any:
        return validate_schemas.Draft202012Validator(
            self.documents[name],
            registry=self.registry,
            format_checker=validate_schemas.FormatChecker(),
        )

    def test_a_profile_with_every_vocabulary_name_is_valid(self) -> None:
        errors = list(self.validator("profile.schema.json").iter_errors(profile()))
        self.assertEqual(errors, [])

    def test_every_profile_kind_refuses_an_unknown_name(self) -> None:
        validator = self.validator("profile.schema.json")
        for kind, path in PROFILE_KINDS.items():
            document = copy.deepcopy(profile())
            replace(document, path, UNKNOWN)
            self.assertFalse(validator.is_valid(document), kind)

    def test_a_profile_refuses_the_spelling_of_every_renamed_kind(self) -> None:
        validator = self.validator("profile.schema.json")
        document = renamed_kinds_profile()
        self.assertEqual(list(validator.iter_errors(document)), [])
        for kind, (path, replaced) in RENAMED_PROFILE_KINDS.items():
            broken = copy.deepcopy(document)
            replace(broken, path, replaced)
            self.assertFalse(validator.is_valid(broken), kind)

    def test_a_report_refuses_the_spelling_of_a_renamed_motor_and_trigger(self) -> None:
        for pointer, accepted, replaced in (
            ("rumbleMotor", "LowFrequency", "leftMain"),
            ("rumbleMotor", "RightHaptic", "rightHaptic"),
        ):
            sub = {"$ref": f"#/$defs/{pointer}"}
            checker = validate_schemas.Draft202012Validator(
                {**sub, "$defs": self.documents["report.schema.json"]["$defs"]},
                format_checker=validate_schemas.FormatChecker(),
            )
            self.assertTrue(checker.is_valid(accepted), accepted)
            self.assertFalse(checker.is_valid(replaced), replaced)
        capabilities = {
            "$ref": "#/$defs/physicalOutputCapabilities",
            "$defs": self.documents["report.schema.json"]["$defs"],
        }
        checker = validate_schemas.Draft202012Validator(capabilities)
        base = {
            "rumbleMotors": [],
            "binaryRumbleMotors": [],
            "lightingFeatures": [],
            "adaptiveTriggers": ["Left", "Right"],
        }
        self.assertTrue(checker.is_valid(base))
        for replaced in ("left", "right"):
            self.assertFalse(checker.is_valid({**base, "adaptiveTriggers": [replaced]}))
        self.assertTrue(checker.is_valid({**base, "speaker": "YamahaADPCM4Bit"}))
        self.assertFalse(checker.is_valid({**base, "speaker": "yamahaADPCM4Bit"}))

    def test_the_output_schema_refuses_the_spelling_of_a_renamed_behavior_and_surface(
        self,
    ) -> None:
        defs = cast(dict[str, Any], self.documents["cli-output.schema.json"]["$defs"])
        behavior = defs["sharedBindingSummary"]["properties"]["behavior"]
        surface = defs["sharedControllerState"]["properties"]["touch"]["items"][
            "properties"
        ]["surface"]
        for node, accepted, replaced in (
            (behavior, "TapOnPress", "tap_on_press"),
            (behavior, "Hold", "hold"),
            (surface, "Primary", "primary"),
            (surface, "Right", "right"),
        ):
            checker = validate_schemas.Draft202012Validator(node)
            self.assertTrue(checker.is_valid(accepted), accepted)
            self.assertFalse(checker.is_valid(replaced), replaced)

    def test_a_profile_with_a_missing_or_unsupported_api_version_is_refused(
        self,
    ) -> None:
        validator = self.validator("profile.schema.json")
        missing = profile()
        del missing["apiVersion"]
        unsupported = {**profile(), "apiVersion": "unsupported.example/v9"}
        for document in (missing, unsupported):
            self.assertFalse(validator.is_valid(document))

    def test_a_profile_of_another_kind_is_refused(self) -> None:
        document = {**profile(), "kind": "Controller"}
        self.assertFalse(self.validator("profile.schema.json").is_valid(document))

    def test_a_gyro_activation_that_is_not_always_needs_a_source(self) -> None:
        document = profile()
        del document["gyroOutput"]["activationSource"]
        self.assertFalse(self.validator("profile.schema.json").is_valid(document))
        document["gyroOutput"]["activationMode"] = "Always"
        self.assertTrue(self.validator("profile.schema.json").is_valid(document))

    def test_a_frame_refuses_an_unknown_d_pad_name(self) -> None:
        validator = self.validator("endpoint.schema.json")
        frame = {"apiVersion": VERSION, "kind": "Frame", "dpad": ["DpadUp"]}
        self.assertTrue(validator.is_valid(frame))
        self.assertFalse(validator.is_valid({**frame, "dpad": [UNKNOWN]}))


if __name__ == "__main__":
    unittest.main()
