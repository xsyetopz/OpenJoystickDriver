from __future__ import annotations

import json
import plistlib
import re
import unittest
from pathlib import Path
from typing import Any

from Scripts.Quality import validate_schemas
from Scripts.SDK import reference_client

ROOT = Path(__file__).resolve().parents[2]
VECTOR = ROOT / "Tests" / "RepositoryScripts" / "fixtures" / "endpoint_hello_proof.json"
PAGE = ROOT / "docs" / "sdk" / "endpoint.md"
CLIENT_KINDS = {
    "Hello",
    "Subscription",
    "FeedRequest",
    "ProfileRequest",
    "ModList",
    "OutputRequest",
    "Frame",
    "KeepAlive",
    "Drain",
}
DOCUMENTED_KINDS = {
    "Challenge",
    "Hello",
    "Welcome",
    "Subscription",
    "FeedRequest",
    "FeedSession",
    "ProfileRequest",
    "ProfileResult",
    "ModList",
    "Mods",
    "OutputRequest",
    "OutputResult",
    "Profiles",
    "Frame",
    "KeepAlive",
    "Drain",
    "Drained",
    "RumbleCommand",
    "Status",
    "AccessGrants",
}


def examples() -> list[dict[str, Any]]:
    """Every `json` block of the page, which holds one JSON object each."""
    text = PAGE.read_text(encoding="utf-8")
    blocks = re.findall(r"^```json\n(.*?)^```$", text, re.MULTILINE | re.DOTALL)
    return [json.loads(block) for block in blocks]


class SDKDocsTests(unittest.TestCase):
    def setUp(self) -> None:
        documents = validate_schemas.validate_schema_documents()
        registry = validate_schemas.schema_registry(documents)

        def validator(schema: str, name: str = "") -> Any:
            reference = documents[schema]["$id"]
            if name:
                reference = f"{reference}#/$defs/{name}"
            return validate_schemas.Draft202012Validator(
                {"$ref": reference}, registry=registry
            )

        self.client_lines = validator("endpoint.schema.json", "clientLine")
        self.service_lines = validator("endpoint.schema.json", "serviceLine")
        self.grants = validator("access-grants.schema.json")

    def validator(self, example: dict[str, Any]) -> Any:
        kind = example.get("kind")
        if kind == "AccessGrants":
            return self.grants
        return self.client_lines if kind in CLIENT_KINDS else self.service_lines

    def test_every_example_validates_against_the_schema(self) -> None:
        for example in examples():
            with self.subTest(example=example):
                self.validator(example).validate(example)

    def test_the_examples_cover_every_message_kind(self) -> None:
        kinds = {example.get("kind") for example in examples()}
        self.assertTrue(DOCUMENTED_KINDS <= kinds, DOCUMENTED_KINDS - kinds)

    def test_the_examples_cover_a_watch_line(self) -> None:
        self.assertTrue(any("type" in example for example in examples()))

    def test_the_examples_name_the_endpoint_api_version(self) -> None:
        for example in examples():
            version = example.get("apiVersion") or example["object"]["apiVersion"]
            self.assertEqual(version, "openjoystickdriver/v1alpha3")

    def test_a_bad_example_would_fail(self) -> None:
        bad = {"apiVersion": "unsupported.example/v9", "kind": "Hello"}
        with self.assertRaises(validate_schemas.ValidationError):
            self.client_lines.validate(bad)

    def endpoint_catalog(self) -> list[dict[str, Any]]:
        catalog = plistlib.loads(
            (ROOT / "Resources" / "ErrorCodes.plist").read_bytes()
        )
        return [entry for entry in catalog["codes"] if entry["domain"] == "Endpoint"]

    def error_rows(self) -> list[tuple[str, str, str]]:
        return re.findall(
            r"^\| `(E\d{4})` \| `(\w+)` \| (.*?) \|$",
            PAGE.read_text(encoding="utf-8"),
            re.MULTILINE,
        )

    def test_the_error_table_lists_every_endpoint_code(self) -> None:
        expected = {entry["code"]: entry["name"] for entry in self.endpoint_catalog()}
        rows = {code: name for code, name, _ in self.error_rows()}
        self.assertEqual(rows, expected)

    def test_every_error_table_row_has_a_meaning(self) -> None:
        for code, _, meaning in self.error_rows():
            with self.subTest(code=code):
                self.assertTrue(meaning, "a code needs a meaning")

    def test_the_hello_example_proof_matches_the_reference_client(self) -> None:
        vector = json.loads(VECTOR.read_text(encoding="utf-8"))
        all_examples = examples()
        challenge = next(e for e in all_examples if e.get("kind") == "Challenge")
        hello = next(e for e in all_examples if "proof" in e)
        self.assertEqual(challenge["nonce"], vector["nonce"])
        self.assertEqual(
            hello["proof"], reference_client.proof(vector["token"], challenge["nonce"])
        )


if __name__ == "__main__":
    unittest.main()
