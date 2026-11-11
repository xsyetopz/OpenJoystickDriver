"""The `schema` flag of each Swift rejection case says whether JSON Schema alone rejects it.

`Tests/OpenJoystickDriverKitTests/Protocol/Catalog/SchemaRejections/` lists the documents the
Swift decoders refuse. A case flagged `schema: true` must fail validation against its schema,
and every other case must pass it, so the schemas stay accurate for editors.
"""

from __future__ import annotations

import json
import unittest
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator

from Scripts.Quality import validate_schemas

ROOT = Path(__file__).resolve().parents[2]
CASES = ROOT / "Tests/OpenJoystickDriverKitTests/Protocol/Catalog/SchemaRejections"
SCHEMAS = {
    "controller": "controller.schema.json",
    "protocol-description": "protocol-description.schema.json",
    "controller-patch": "controller-patch.schema.json",
}


class SchemaRejectionFlagTests(unittest.TestCase):
    def test_flag_matches_the_schema(self) -> None:
        documents = validate_schemas.validate_schema_documents()
        registry = validate_schemas.schema_registry(documents)
        for kind, schema in SCHEMAS.items():
            validator = Draft202012Validator(documents[schema], registry=registry)
            cases: list[dict[str, Any]] = json.loads(
                (CASES / f"{kind}.json").read_text(encoding="utf-8")
            )["cases"]
            self.assertTrue(cases, kind)
            for case in cases:
                with self.subTest(kind=kind, name=case["name"]):
                    self.assertEqual(
                        set(case) - {"schema", "fileName"},
                        {"name", "code", "document"},
                    )
                    self.assertEqual(
                        not validator.is_valid(case["document"]),
                        case.get("schema") is True,
                        "the schema flag must be true exactly when the schema rejects the document",
                    )


if __name__ == "__main__":
    unittest.main()
