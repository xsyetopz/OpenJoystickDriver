"""A document of each kind that its JSON Schema accepts and `OJDRepositoryTool` accepts too.

`test_schema_rejection_flags.py` and `SchemaRejectionTests` cover the documents that are refused;
this covers the other direction, so a schema that is stricter than Swift fails here.
"""

from __future__ import annotations

import json
import plistlib
import unittest
from pathlib import Path

from Scripts.Quality import repository_tool, validate_schemas

ROOT = Path(__file__).resolve().parents[2]
RECORD = (
    ROOT / "Sources/OpenJoystickDriverKit/Resources/Controllers/045e/045e-028e.plist"
)
DESCRIPTION = ROOT / "Resources/Protocols/nintendo-switch-input-only.plist"
PROFILE = ROOT / "docs/sdk/sample/Profiles/sample-pad.plist"


class SchemaAcceptedDocumentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.documents = validate_schemas.validate_schema_documents()
        cls.registry = validate_schemas.schema_registry(cls.documents)

    def assert_schema_accepts(self, schema: str, path: Path) -> None:
        validator = validate_schemas.Draft202012Validator(
            self.documents[schema], registry=self.registry
        )
        validator.validate(
            plistlib.loads(path.read_bytes())
            if path.suffix == ".plist"
            else json.loads(path.read_text(encoding="utf-8"))
        )

    def test_a_controller_record_is_accepted_by_the_schema_and_by_swift(self) -> None:
        self.assert_schema_accepts("controller.schema.json", RECORD)
        repository_tool.check(["validate", "controllers", str(RECORD.parents[1])])

    def test_a_protocol_description_is_accepted_by_the_schema_and_by_swift(
        self,
    ) -> None:
        self.assert_schema_accepts("protocol-description.schema.json", DESCRIPTION)
        repository_tool.check(["validate", "descriptions", str(DESCRIPTION.parent)])

    def test_a_profile_is_accepted_by_the_schema_and_by_swift(self) -> None:
        self.assert_schema_accepts("profile.schema.json", PROFILE)
        repository_tool.check(["validate", "profiles", str(PROFILE)])


if __name__ == "__main__":
    unittest.main()
