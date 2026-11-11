from __future__ import annotations

import json
import plistlib
import unittest
from typing import Any

from Scripts.Quality import validate_schemas

VERSION = "openjoystickdriver/v1alpha3"
ROOT = validate_schemas.ROOT
CROSSWALK = ROOT / "Resources" / "Vocabulary" / "crosswalk.plist"
SAMPLE_PROFILE = ROOT / "docs" / "sdk" / "sample" / "Profiles" / "sample-pad.plist"

# Names that are not control ids.
UNKNOWN_NAMES = ["notAName", "NotAControl", ""]


class ControlVocabularyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.documents = validate_schemas.validate_schema_documents()
        cls.registry = validate_schemas.schema_registry(cls.documents)
        defs = cls.documents["vocabulary.schema.json"]["$defs"]
        assert isinstance(defs, dict)
        cls.controls: list[str] = defs["control"]["enum"]
        document = plistlib.loads(CROSSWALK.read_bytes())
        cls.crosswalk: dict[str, dict[str, Any]] = document["controls"]
        cls.sources: dict[str, dict[str, Any]] = document["sources"]

    def validator(self, name: str) -> Any:
        return validate_schemas.Draft202012Validator(
            self.documents[name],
            registry=self.registry,
            format_checker=validate_schemas.FormatChecker(),
        )

    def test_every_id_is_upper_camel_case(self) -> None:
        for control in self.controls:
            self.assertRegex(control, r"^[A-Z][A-Za-z0-9]*$")

    def test_the_crosswalk_has_one_row_per_control(self) -> None:
        self.assertEqual(sorted(self.crosswalk), sorted(self.controls))

    def test_the_crosswalk_round_trips_every_control(self) -> None:
        indexes: dict[str, dict[Any, set[str]]] = {
            "sdl": {},
            "evdev": {},
            "apple": {},
            "hid": {},
            "w3cButton": {},
            "w3cAxis": {},
        }
        for control, row in self.crosswalk.items():
            for column, index in indexes.items():
                if column == "hid":
                    keys: list[Any] = [
                        (entry["page"], entry["usage"])
                        for entry in row.get("hid", [])
                        if entry.get("usage")
                    ]
                else:
                    keys = [row[column]] if column in row else []
                for key in keys:
                    index.setdefault(key, set()).add(control)
        for control, row in self.crosswalk.items():
            for column, index in indexes.items():
                if column == "hid":
                    keys = [
                        (e["page"], e["usage"])
                        for e in row.get("hid", [])
                        if e.get("usage")
                    ]
                else:
                    keys = [row[column]] if column in row else []
                for key in keys:
                    self.assertIn(control, index[key], f"{control} via {column}")
        self.assertEqual(indexes["sdl"]["MISC1"], {"Capture", "Microphone"})
        self.assertEqual(indexes["sdl"]["SOUTH"], {"South"})

    def test_every_column_records_its_source(self) -> None:
        self.assertEqual(set(self.sources), {"w3c", "sdl", "evdev", "hid", "apple"})
        for column, source in self.sources.items():
            for field in ("document", "version", "url", "checkedOn"):
                self.assertTrue(source.get(field), f"{column} source {field}")
            self.assertTrue(source["url"].startswith("https://"), column)
        self.assertRegex(self.sources["sdl"]["revision"], r"^[0-9a-f]{40}$")
        self.assertRegex(self.sources["evdev"]["revision"], r"^[0-9a-f]{40}$")

    def test_every_hid_page_is_a_page_of_the_hid_source(self) -> None:
        pages = self.sources["hid"]["pages"]
        for control, row in self.crosswalk.items():
            for entry in row.get("hid", []):
                self.assertIn(entry["page"], pages, control)

    def test_a_note_names_a_column_of_the_table(self) -> None:
        for control, row in self.crosswalk.items():
            for column in row.get("notes", {}):
                self.assertIn(column, self.sources, control)

    def test_the_sourced_cells_hold(self) -> None:
        rows = self.crosswalk
        simulation = {"page": "Simulation"}
        self.assertIn({**simulation, "usage": 197}, rows["LeftTrigger"]["hid"])
        self.assertIn({**simulation, "usage": 196}, rows["RightTrigger"]["hid"])
        self.assertEqual(rows["TouchpadClick"]["evdev"], "BTN_LEFT")
        self.assertEqual(rows["TouchpadClick"]["apple"], "DualShockTouchpadButton")
        self.assertEqual(rows["RightPaddle1"]["apple"], "XboxPaddleOne")
        self.assertEqual(rows["RightPaddle2"]["apple"], "XboxPaddleTwo")
        self.assertEqual(rows["LeftPaddle1"]["apple"], "XboxPaddleThree")
        self.assertEqual(rows["LeftPaddle2"]["apple"], "XboxPaddleFour")
        self.assertEqual(
            rows["DpadUp"]["hid"][0], {"page": "GenericDesktop", "usage": 144}
        )
        self.assertEqual(rows["Capture"]["hid"], [{"page": "Consumer", "usage": 178}])

    def test_no_control_without_a_name_has_a_guess(self) -> None:
        for control in (
            "LeftStickTouch",
            "LeftTrackpadClick",
            "RightTrackpadTouch",
            "LeftGripTouch",
            "RightGripTouch",
        ):
            row = self.crosswalk[control]
            for column in ("w3cButton", "w3cAxis", "sdl", "evdev", "hid", "apple"):
                self.assertNotIn(column, row, f"{control} {column}")

    def test_a_profile_with_a_current_name_is_valid(self) -> None:
        with SAMPLE_PROFILE.open("rb") as source:
            profile = plistlib.load(source)
        self.assertTrue(self.validator("profile.schema.json").is_valid(profile))

    def test_a_profile_naming_an_unknown_control_is_refused(self) -> None:
        validator = self.validator("profile.schema.json")
        with SAMPLE_PROFILE.open("rb") as source:
            profile = plistlib.load(source)
        for name in UNKNOWN_NAMES:
            profile["bindings"][0]["source"]["button"] = name
            self.assertFalse(validator.is_valid(profile), name)

    def test_an_endpoint_frame_naming_an_unknown_control_is_refused(self) -> None:
        validator = self.validator("endpoint.schema.json")
        frame = {"apiVersion": VERSION, "kind": "Frame", "buttons": ["South"]}
        self.assertTrue(validator.is_valid(frame))
        for name in UNKNOWN_NAMES:
            self.assertFalse(validator.is_valid({**frame, "buttons": [name]}), name)
            self.assertFalse(validator.is_valid({**frame, "axes": {name: 0.5}}), name)


if __name__ == "__main__":
    unittest.main()
