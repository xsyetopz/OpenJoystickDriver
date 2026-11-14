"""Style rule for every `description` in Resources/Schemas.

A description is one sentence fragment of at most 120 characters that ends with a period and says what
the value is. It names no Swift type, path, command, error code, or validator. No schema holds a
`$comment`. A failure names the schema file and the JSON pointer of the keyword.
"""

from __future__ import annotations

import json
import re
import unittest
from collections.abc import Iterator
from pathlib import Path
from typing import Any, cast

ROOT = Path(__file__).resolve().parents[2]
SCHEMAS = ROOT / "Resources" / "Schemas"
SOURCES = ROOT / "Sources"

MAX_LENGTH = 120
# Keywords whose value is data, not a schema to descend into.
DATA_KEYWORDS = ("enum", "const", "default", "examples")

SWIFT_DECLARATION = re.compile(
    r"\b(?:struct|class|enum|protocol|actor|typealias)\s+([A-Z][A-Za-z0-9]*)"
)
UPPER_CAMEL = re.compile(r"\b[A-Z][a-z0-9]+(?:[A-Z][A-Za-z0-9]*)+\b")
SENTENCE_BREAK = re.compile(r"[.!?]\s+[A-Z]")
PATH = re.compile(
    r"\b\w[\w-]*\.(?:swift|json|md|py|plist|txt|sh)\b|(?:^|\s)[~.]{0,2}/\w|\b(?:Sources|Resources|Scripts|Tests|wiki)/|\w/\w+/\w"
)
COMMAND = re.compile(r"\bojd\b")
ERROR_CODE = re.compile(r"\bE\d{4}\b")
VALIDATOR_WORDING = re.compile(
    r"\b(?:must|required|requires?|validators?|validat\w*|rejects?|rejected|schema)\b",
    re.IGNORECASE,
)


def escape(name: str) -> str:
    return name.replace("~", "~0").replace("/", "~1")


def swift_types() -> set[str]:
    """Every type name declared under Sources/."""
    names: set[str] = set()
    for path in SOURCES.rglob("*.swift"):
        names.update(SWIFT_DECLARATION.findall(path.read_text(encoding="utf-8")))
    return names


def keywords(node: Any, pointer: str = "") -> Iterator[tuple[str, str, Any]]:
    """Yield `(pointer, key, value)` for each schema keyword in `node` and below."""
    if isinstance(node, list):
        for index, item in enumerate(cast("list[Any]", node)):
            yield from keywords(item, f"{pointer}/{index}")
    elif isinstance(node, dict):
        for key, value in cast("dict[str, Any]", node).items():
            here = f"{pointer}/{escape(key)}"
            yield here, key, value
            if key not in DATA_KEYWORDS:
                yield from keywords(value, here)


def problems(text: str, types: set[str]) -> list[str]:
    """The rules one description breaks."""
    found: list[str] = []
    if SENTENCE_BREAK.search(text):
        found.append("more than one sentence")
    if len(text) > MAX_LENGTH:
        found.append(f"{len(text)} characters, over {MAX_LENGTH}")
    if not text.endswith("."):
        found.append("does not end with a period")
    if "`" in text or types.intersection(UPPER_CAMEL.findall(text)):
        found.append("names a Swift type or code")
    if PATH.search(text):
        found.append("names a path")
    if COMMAND.search(text):
        found.append("names an ojd command")
    if ERROR_CODE.search(text):
        found.append("names an error code")
    if VALIDATOR_WORDING.search(text):
        found.append("uses validator wording")
    return found


def violations() -> list[tuple[str, str, str]]:
    """Every `(schema file, JSON pointer, reason)` that breaks the rule."""
    types = swift_types()
    found: list[tuple[str, str, str]] = []
    for path in sorted(SCHEMAS.glob("*.schema.json")):
        document = json.loads(path.read_text(encoding="utf-8"))
        for pointer, key, value in keywords(document):
            if key == "$comment":
                found.append((path.name, pointer, "holds a $comment"))
            elif key == "description" and isinstance(value, str):
                found.extend((path.name, pointer, p) for p in problems(value, types))
    return found


class SchemaStyleTests(unittest.TestCase):
    def test_there_are_sixteen_schema_files(self) -> None:
        self.assertEqual(len(list(SCHEMAS.glob("*.schema.json"))), 16)

    def test_every_description_follows_the_style_and_no_schema_holds_a_comment(
        self,
    ) -> None:
        found = [
            f"{name} {pointer}: {reason}" for name, pointer, reason in violations()
        ]
        self.assertEqual(found, [], f"{len(found)} style failures")

    def test_the_rules_accept_a_plain_fragment_and_reject_each_breach(self) -> None:
        types = {"ControllerRecord"}
        self.assertEqual(problems("The USB vendor identifier.", types), [])
        for text in (
            "One. Two.",
            "x" * 120 + ".",
            "No period",
            "Like ControllerRecord.",
            "The `code` value.",
            "Read from Sources/x.",
            "Set by ojd record.",
            "Fails with E5007.",
            "The value must be set.",
        ):
            with self.subTest(text=text):
                self.assertNotEqual(problems(text, types), [])


if __name__ == "__main__":
    unittest.main()
