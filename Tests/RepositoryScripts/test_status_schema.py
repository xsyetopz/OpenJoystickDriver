from __future__ import annotations

import copy
import unittest
from typing import Any

from Scripts.Catalog import schema_header
from Scripts.Quality import validate_schemas

SCHEMA = "cli-output.schema.json"
LINK_STATES = ("Installed", "LinkedElsewhere", "Broken", "BlockedByFile", "Missing")
SETTING_KEYS = [
    "launchAtLogin",
    "showInMenuBar",
    "showInDock",
    "notify.controllerConnected",
    "notify.controllerDisconnected",
    "notify.profileActivated",
    "notify.profileDeactivated",
    "notify.sounds",
    "updates.checkAutomatically",
    "updates.includePrereleases",
    "developerTools",
]


def status_document(state: str = "Installed") -> dict[str, Any]:
    tool = {"path": "/usr/local/bin/ojd", "state": state}
    if state not in ("Missing", "BlockedByFile"):
        tool["target"] = (
            "/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver"
        )
    return {
        **schema_header.header("SystemStatus"),
        "commandLineTool": tool,
        "transportExtension": {"bundle": "Present", "registration": "Active"},
        "service": {"state": "Running"},
        "skippedRecords": [],
    }


class StatusSchemaTests(unittest.TestCase):
    def setUp(self) -> None:
        documents = validate_schemas.validate_schema_documents()
        self.schema: dict[str, Any] = documents[SCHEMA]
        status = {"$ref": "#/$defs/status", "$defs": self.schema["$defs"]}
        self.validator = validate_schemas.Draft202012Validator(
            status,
            registry=validate_schemas.schema_registry(documents),
            format_checker=validate_schemas.FormatChecker(),
        )

    def test_accepts_each_command_line_tool_state(self) -> None:
        for state in LINK_STATES:
            with self.subTest(state=state):
                self.validator.validate(status_document(state))

    def test_accepts_the_target_of_a_link(self) -> None:
        document = status_document("LinkedElsewhere")
        document["commandLineTool"]["target"] = "/Applications/Other.app/ojd"

        self.validator.validate(document)

    def test_rejects_an_unknown_command_line_tool_state(self) -> None:
        for state in (
            "linked",
            "notALink",
            "",
            "installed",
            "linkedElsewhere",
            "broken",
            "blockedByFile",
            "missing",
        ):
            with (
                self.subTest(state=state),
                self.assertRaises(validate_schemas.ValidationError),
            ):
                self.validator.validate(status_document(state))

    def test_rejects_a_missing_command_line_tool_block(self) -> None:
        document = copy.deepcopy(status_document())
        del document["commandLineTool"]

        with self.assertRaises(validate_schemas.ValidationError):
            self.validator.validate(document)

    def test_rejects_an_unknown_member(self) -> None:
        document = status_document()
        document["notAMember"] = 1

        with self.assertRaises(validate_schemas.ValidationError):
            self.validator.validate(document)

    def test_the_shared_setting_key_enum_lists_every_setting(self) -> None:
        self.assertEqual(self.schema["$defs"]["sharedSettingKey"]["enum"], SETTING_KEYS)


if __name__ == "__main__":
    unittest.main()
