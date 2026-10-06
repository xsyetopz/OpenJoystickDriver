"""Behavior tests for the release-to-release `cli-output.schema.json` compatibility check."""

from __future__ import annotations

import copy
import json
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import Any

from Scripts.Quality import schema_compatibility

ROOT = "cli-output.schema.json"


def documents() -> dict[str, dict[str, Any]]:
    return {
        ROOT: {
            "$defs": {
                "controllerList": {
                    "type": "object",
                    "required": ["controllers"],
                    "additionalProperties": False,
                    "properties": {
                        "controllers": {
                            "type": "array",
                            "items": {"$ref": "#/$defs/sharedDevice"},
                        }
                    },
                },
                "controllerWatch": {
                    "oneOf": [
                        {"$ref": "#/$defs/sharedDevice"},
                        {
                            "type": "object",
                            "required": ["control"],
                            "properties": {"control": {"type": "string"}},
                        },
                    ]
                },
                "sharedDevice": {
                    "type": "object",
                    "required": ["id", "session"],
                    "additionalProperties": False,
                    "properties": {
                        "id": {"type": "string"},
                        "battery": {"type": "integer"},
                        "session": {"enum": ["active", "suspended"]},
                        "power": {
                            "$ref": "report.schema.json#/$defs/power",
                        },
                    },
                },
            }
        },
        "report.schema.json": {
            "$defs": {
                "power": {
                    "type": "object",
                    "properties": {"charging": {"const": "charging"}},
                }
            }
        },
    }


class BreakingChangesTests(unittest.TestCase):
    def changes(self, new: dict[str, dict[str, Any]]) -> list[str]:
        return schema_compatibility.breaking_changes(documents(), new)

    def test_an_unchanged_schema_passes(self) -> None:
        self.assertEqual(self.changes(documents()), [])

    def test_added_keys_values_branches_and_commands_pass(self) -> None:
        new = documents()
        defs = new[ROOT]["$defs"]
        defs["sharedDevice"]["properties"]["name"] = {"type": "string"}
        defs["sharedDevice"]["properties"]["session"]["enum"].append("closed")
        defs["controllerWatch"]["oneOf"].append({"type": "object"})
        defs["controllerShow"] = {"type": "object"}
        self.assertEqual(self.changes(new), [])

    def test_a_newly_required_key_or_a_narrower_type_passes(self) -> None:
        new = documents()
        device = new[ROOT]["$defs"]["sharedDevice"]
        device["required"].append("battery")
        device["properties"]["id"]["type"] = "string"
        old = documents()
        old[ROOT]["$defs"]["sharedDevice"]["properties"]["id"]["type"] = [
            "string",
            "null",
        ]
        self.assertEqual(schema_compatibility.breaking_changes(old, new), [])

    def test_a_removed_property_fails(self) -> None:
        new = documents()
        del new[ROOT]["$defs"]["sharedDevice"]["properties"]["battery"]
        self.assertEqual(
            self.changes(new),
            [f"{ROOT}#/$defs/sharedDevice/properties/battery: property removed"],
        )

    def test_a_removed_enum_or_const_value_fails(self) -> None:
        new = documents()
        new[ROOT]["$defs"]["sharedDevice"]["properties"]["session"]["enum"] = ["active"]
        new["report.schema.json"]["$defs"]["power"]["properties"]["charging"] = {
            "const": "full"
        }
        self.assertEqual(
            self.changes(new),
            [
                f'{ROOT}#/$defs/sharedDevice/properties/session: value "suspended" removed',
                'report.schema.json#/$defs/power/properties/charging: value "charging" removed',
            ],
        )

    def test_a_key_that_is_no_longer_required_fails(self) -> None:
        new = documents()
        new[ROOT]["$defs"]["sharedDevice"]["required"] = ["id"]
        self.assertEqual(
            self.changes(new),
            [f'{ROOT}#/$defs/sharedDevice: key "session" no longer required'],
        )

    def test_a_wider_type_fails(self) -> None:
        new = documents()
        properties = new[ROOT]["$defs"]["sharedDevice"]["properties"]
        properties["id"]["type"] = ["string", "null"]
        properties["battery"]["type"] = "number"
        properties["session"] = {"type": "string"}
        self.assertEqual(
            self.changes(new),
            [
                f"{ROOT}#/$defs/sharedDevice/properties/id: can now be null",
                f"{ROOT}#/$defs/sharedDevice/properties/battery: can now be number",
            ],
        )

    def test_an_untyped_value_fails(self) -> None:
        new = documents()
        new[ROOT]["$defs"]["sharedDevice"]["properties"]["id"] = {}
        self.assertEqual(
            self.changes(new),
            [f"{ROOT}#/$defs/sharedDevice/properties/id: can now be any type"],
        )

    def test_a_removed_command_output_or_branch_fails(self) -> None:
        new = documents()
        defs = new[ROOT]["$defs"]
        del defs["controllerList"]
        defs["controllerWatch"]["oneOf"].pop()
        self.assertEqual(
            self.changes(new),
            [
                f"{ROOT}#/$defs/controllerList: command output removed",
                f"{ROOT}#/$defs/controllerWatch/oneOf/1: branch removed",
            ],
        )

    def test_matches_conditional_constraints_by_their_condition(self) -> None:
        def conditional(family: str, quirks: list[str]) -> dict[str, Any]:
            return {
                "if": {"properties": {"family": {"const": family}}},
                "then": {"properties": {"quirks": {"enum": quirks}}},
            }

        old = documents()
        old[ROOT]["$defs"]["sharedDevice"]["allOf"] = [
            conditional("pad", ["a", "b"]),
            conditional("stick", ["c"]),
        ]
        new = copy.deepcopy(old)
        new[ROOT]["$defs"]["sharedDevice"]["allOf"].insert(
            0, conditional("wheel", ["d"])
        )
        self.assertEqual(schema_compatibility.breaking_changes(old, new), [])

        new[ROOT]["$defs"]["sharedDevice"]["allOf"][1] = conditional("pad", ["a"])
        new[ROOT]["$defs"]["sharedDevice"]["allOf"].pop()
        self.assertEqual(
            schema_compatibility.breaking_changes(old, new),
            [
                f'{ROOT}#/$defs/sharedDevice/allOf/0/then/properties/quirks: value "b" removed',
                f"{ROOT}#/$defs/sharedDevice/allOf/1: branch removed",
            ],
        )

    def test_follows_references_on_both_sides(self) -> None:
        new = documents()
        defs = new[ROOT]["$defs"]
        # The new schema inlines the device and moves power under another name.
        defs["controllerList"]["properties"]["controllers"]["items"] = copy.deepcopy(
            defs["sharedDevice"]
        )
        report = new["report.schema.json"]["$defs"]
        report["batteryPower"] = copy.deepcopy(report["power"])
        defs["sharedDevice"]["properties"]["power"]["$ref"] = (
            "report.schema.json#/$defs/batteryPower"
        )
        self.assertEqual(self.changes(new), [])

        del defs["controllerList"]["properties"]["controllers"]["items"]["properties"][
            "id"
        ]
        self.assertEqual(
            self.changes(new),
            [f"{ROOT}#/$defs/sharedDevice/properties/id: property removed"],
        )


def git(root: Path, *args: str) -> str:
    return subprocess.run(
        [
            "git",
            "-c",
            "user.name=Test",
            "-c",
            "user.email=test@example.com",
            "-c",
            "commit.gpgsign=false",
            "-c",
            "tag.gpgsign=false",
            *args,
        ],
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
    ).stdout


class BaselineTests(unittest.TestCase):
    def make_repository(self) -> Path:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        git(root, "init", "--quiet")
        (root / "Resources" / "Schemas").mkdir(parents=True)
        return root

    def commit(self, root: Path, name: str, document: object) -> None:
        (root / "Resources" / "Schemas" / name).write_text(
            json.dumps(document), encoding="utf-8"
        )
        git(root, "add", ".")
        git(root, "commit", "--quiet", "-m", name)

    def test_has_no_baseline_when_the_release_lacks_the_schema(self) -> None:
        root = self.make_repository()
        self.commit(root, "report.schema.json", {})
        git(root, "tag", "0.1.0")
        self.commit(root, ROOT, {"$defs": {}})

        self.assertEqual(schema_compatibility.last_release_tag(root), "0.1.0")
        self.assertIsNone(schema_compatibility.documents_at(root, "0.1.0"))

    def test_reads_the_schemas_from_the_versioned_directory(self) -> None:
        root = self.make_repository()
        versioned = root / "Resources" / "Schemas" / "v1beta1"
        versioned.mkdir()
        (versioned / ROOT).write_text(
            json.dumps({"$defs": {"a": {}}}), encoding="utf-8"
        )
        (versioned / "report.schema.json").write_text("{}", encoding="utf-8")
        git(root, "add", ".")
        git(root, "commit", "--quiet", "-m", "versioned")
        git(root, "tag", "0.1.0")

        self.assertEqual(
            schema_compatibility.documents_at(root, "0.1.0"),
            {ROOT: {"$defs": {"a": {}}}, "report.schema.json": {}},
        )

    def test_a_release_commit_compares_with_the_release_before_it(self) -> None:
        root = self.make_repository()
        self.commit(root, ROOT, {"$defs": {"a": {}}})
        git(root, "tag", "0.1.0")
        self.commit(root, ROOT, {"$defs": {"b": {}}})
        git(root, "tag", "0.2.0")

        self.assertEqual(schema_compatibility.last_release_tag(root), "0.1.0")
        self.assertEqual(
            schema_compatibility.documents_at(root, "0.1.0"),
            {ROOT: {"$defs": {"a": {}}}},
        )

    def test_only_a_new_major_version_can_break_the_last_release(self) -> None:
        root = self.make_repository()
        plist = root / "Sources" / "OpenJoystickDriver" / "App" / "Info.plist"
        plist.parent.mkdir(parents=True)
        self.commit(root, ROOT, {"$defs": {"controllerList": {}}})
        git(root, "tag", "0.1.0")
        self.commit(root, ROOT, {"$defs": {}})
        current = {ROOT: {"$defs": {}}}

        plist.write_bytes(
            plistlib.dumps({"CFBundleShortVersionString": "0.2.0-beta.1"})
        )
        with self.assertRaises(schema_compatibility.IncompatibleSchemaError) as raised:
            schema_compatibility.check(root, current)
        self.assertIn("controllerList: command output removed", str(raised.exception))

        plist.write_bytes(plistlib.dumps({"CFBundleShortVersionString": "1.0.0"}))
        self.assertIn("1.0.0", schema_compatibility.check(root, current))


if __name__ == "__main__":
    unittest.main()
