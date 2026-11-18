from __future__ import annotations

import copy
import plistlib
import unittest
from pathlib import Path
from typing import Any

from Scripts.Quality import validate_schemas

FIXTURE = Path(__file__).resolve().parent / "fixtures" / "access_grants.plist"


class AccessGrantsSchemaTests(unittest.TestCase):
    def setUp(self) -> None:
        documents = validate_schemas.validate_schema_documents()
        self.validator = validate_schemas.Draft202012Validator(
            documents["access-grants.schema.json"],
            registry=validate_schemas.schema_registry(documents),
            format_checker=validate_schemas.FormatChecker(),
        )
        with FIXTURE.open("rb") as source:
            self.document: dict[str, Any] = plistlib.load(source)

    def test_the_fixture_is_accepted(self) -> None:
        self.assertTrue(self.validator.is_valid(self.document))

    def test_a_scope_in_the_earlier_spelling_is_refused(self) -> None:
        for scope in ("read", "control", "Reads"):
            with self.subTest(scope=scope):
                document = copy.deepcopy(self.document)
                document["grants"][0]["scopes"] = [scope]
                self.assertFalse(self.validator.is_valid(document))

    def test_a_publisher_kind_in_the_earlier_spelling_is_refused(self) -> None:
        for kind in ("signed", "platform", "adHoc"):
            with self.subTest(kind=kind):
                document = copy.deepcopy(self.document)
                document["grants"][0]["publisher"]["kind"] = kind
                self.assertFalse(self.validator.is_valid(document))

    def test_a_platform_grant_needs_no_publisher_id(self) -> None:
        document = copy.deepcopy(self.document)
        document["grants"][0]["publisher"] = {"kind": "Platform"}
        self.assertTrue(self.validator.is_valid(document))


if __name__ == "__main__":
    unittest.main()
