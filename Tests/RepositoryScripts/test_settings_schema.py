from __future__ import annotations

import unittest
from typing import Any

from Scripts.Quality import validate_schemas

HEADER = {"apiVersion": "openjoystickdriver/v1alpha3", "kind": "Settings"}


class SettingsSchemaTests(unittest.TestCase):
    def setUp(self) -> None:
        documents = validate_schemas.validate_schema_documents()
        self.validator = validate_schemas.Draft202012Validator(
            documents["settings.schema.json"],
            registry=validate_schemas.schema_registry(documents),
        )

    def valid(self, **settings: Any) -> bool:
        return self.validator.is_valid({**HEADER, **settings})

    def test_a_file_that_leaves_every_setting_out_is_accepted(self) -> None:
        self.assertTrue(self.valid())

    def test_the_last_visible_entry_point_cannot_be_turned_off(self) -> None:
        self.assertFalse(self.valid(showInMenuBar=False))
        self.assertFalse(self.valid(showInMenuBar=False, showInDock=False))
        self.assertTrue(self.valid(showInMenuBar=False, showInDock=True))
        self.assertTrue(self.valid(showInDock=False))

    def test_the_interface_level_is_simple_or_advanced(self) -> None:
        self.assertTrue(self.valid(interfaceLevel="Simple"))
        self.assertTrue(self.valid(interfaceLevel="Advanced"))
        for other in ("Expert", "simple", "", True, None):
            with self.subTest(other=other):
                self.assertFalse(self.valid(interfaceLevel=other))


if __name__ == "__main__":
    unittest.main()
