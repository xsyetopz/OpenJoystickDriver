from __future__ import annotations

import copy
import json
import plistlib
import unittest
from pathlib import Path
from typing import Any

from Scripts.Catalog import schema_header
from Scripts.Quality import repository_tool, validate_schemas

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).resolve().parent / "fixtures"
SAMPLE = ROOT / "docs" / "sdk" / "sample"
WRONG_VERSIONS = ("unsupported.example/v9", "openjoystickdriver/v1", "")


def load(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def load_plist(path: Path) -> dict[str, Any]:
    return plistlib.loads(path.read_bytes())


def instances() -> dict[str, dict[str, Any]]:
    """One valid document for each kind that has a header, by schema stem."""
    controller = next(
        (ROOT / "Sources/OpenJoystickDriverKit/Resources/Controllers").glob("*/*.plist")
    )
    return {
        "controller": load_plist(controller),
        "controller-patch": {
            **schema_header.header("ControllerPatch"),
            "selector": {"vendorID": 0x1209, "productID": 1},
            "patch": {"tuning": {"stickDeadzone": 0.02}},
        },
        "virtual-device": load_plist(SAMPLE / "VirtualDevices/1209-0001.plist"),
        "profile": load_plist(SAMPLE / "Profiles/sample-pad.plist"),
        "mod-package": load_plist(SAMPLE / "mod.plist"),
        "error-codes": load_plist(ROOT / "Resources/ErrorCodes.plist"),
        "crosswalk": load_plist(ROOT / "Resources/Vocabulary/crosswalk.plist"),
        "access-grants": load_plist(FIXTURES / "access_grants.plist"),
        "protocol-description": load_plist(ROOT / "Resources/Protocols/xbox-xusb.plist"),
        "settings": load_plist(FIXTURES / "settings.plist"),
        "service-listener-failure": load_plist(FIXTURES / "service_listener_failure.plist"),
    }


class SchemaHeaderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.documents = validate_schemas.validate_schema_documents()
        cls.registry = validate_schemas.schema_registry(cls.documents)

    def validator(self, stem: str) -> Any:
        return validate_schemas.Draft202012Validator(
            self.documents[f"{stem}.schema.json"], registry=self.registry
        )

    def test_every_schema_uses_the_constant_and_its_own_id(self) -> None:
        validate_schemas.validate_schema_identity(self.documents)
        for name, document in self.documents.items():
            with self.subTest(schema=name):
                self.assertEqual(
                    document["$id"], schema_header.schema_id(name.split(".")[0])
                )
                consts = validate_schemas.api_version_consts(document)
                self.assertTrue(
                    all(const == repository_tool.api_version() for _, const in consts)
                )

    def test_every_header_kind_has_a_schema_and_an_instance(self) -> None:
        self.assertEqual(set(instances()), set(schema_header.KINDS))
        for stem in schema_header.KINDS:
            self.assertIn(f"{stem}.schema.json", self.documents)

    def test_accepts_each_kind_with_its_header(self) -> None:
        for stem, document in instances().items():
            with self.subTest(kind=schema_header.KINDS[stem]):
                self.assertEqual(
                    {k: document[k] for k in ("apiVersion", "kind")},
                    schema_header.header(schema_header.KINDS[stem]),
                )
                self.validator(stem).validate(document)

    def test_rejects_each_kind_with_a_missing_or_wrong_header(self) -> None:
        for stem, document in instances().items():
            kind = schema_header.KINDS[stem]
            changes: list[tuple[str, Any]] = [
                ("apiVersion", None),
                ("kind", None),
                ("kind", "Other"),
                ("kind", next(k for k in schema_header.KINDS.values() if k != kind)),
                *(("apiVersion", version) for version in WRONG_VERSIONS),
            ]
            for member, value in changes:
                with self.subTest(kind=kind, member=member, value=value):
                    changed = copy.deepcopy(document)
                    if value is None:
                        del changed[member]
                    else:
                        changed[member] = value
                    with self.assertRaises(validate_schemas.ValidationError):
                        self.validator(stem).validate(changed)

    def test_rejects_a_schema_member(self) -> None:
        for stem, document in instances().items():
            with self.subTest(kind=schema_header.KINDS[stem]):
                changed = {**document, "$schema": schema_header.schema_id(stem)}
                with self.assertRaises(validate_schemas.ValidationError):
                    self.validator(stem).validate(changed)

    def test_rejects_an_invalid_pause_shortcut(self) -> None:
        document = instances()["settings"]
        shortcuts = {
            "no modifier": {"key": "P", "modifiers": []},
            "shift only": {"key": "P", "modifiers": ["shift"]},
            "repeated modifier": {"key": "P", "modifiers": ["command", "command"]},
            "unknown key": {"key": "Home", "modifiers": ["command"]},
            "unknown member": {"key": "P", "modifiers": ["command"], "extra": True},
            "no key": {"modifiers": ["command"]},
        }
        for name, shortcut in shortcuts.items():
            with self.subTest(name):
                with self.assertRaises(validate_schemas.ValidationError):
                    self.validator("settings").validate({**document, "pauseShortcut": shortcut})

    def test_rejects_an_invalid_last_shown_changelog_version(self) -> None:
        document = instances()["settings"]
        for name, version in {"empty": "", "number": 3, "boolean": True}.items():
            with self.subTest(name):
                with self.assertRaises(validate_schemas.ValidationError):
                    self.validator("settings").validate(
                        {**document, "lastShownChangelogVersion": version}
                    )

    def test_no_schema_directory_is_versioned(self) -> None:
        directories = [p for p in (ROOT / "Resources/Schemas").iterdir() if p.is_dir()]
        self.assertEqual(directories, [])


if __name__ == "__main__":
    unittest.main()
