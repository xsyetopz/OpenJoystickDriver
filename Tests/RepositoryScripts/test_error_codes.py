from __future__ import annotations

import json
import plistlib
import shutil
import tempfile
import unittest
from pathlib import Path
from typing import Any

from Scripts.Catalog import generate_error_codes as errors
from Scripts.Catalog.schema_header import header
from Scripts.Quality.repository_tool import command_line_exit_statuses

ROOT = Path(__file__).resolve().parents[2]
COPIED = (
    errors.CATALOG,
    errors.CATALOG_SCHEMA,
    errors.ENDPOINT_SCHEMA,
    errors.WIKI_PAGE,
    errors.ENGLISH_STRINGS,
)


def entry(code: str, domain: str, name: str, **extra: Any) -> dict[str, Any]:
    return {"code": code, "domain": domain, "name": name, **extra}


class ErrorCodeTests(unittest.TestCase):
    def copy_repository(self) -> Path:
        directory = Path(tempfile.mkdtemp(prefix="ojd-errors-"))
        self.addCleanup(shutil.rmtree, directory)
        for path in COPIED:
            (directory / path).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(ROOT / path, directory / path)
        return directory

    def write_catalog(self, root: Path, codes: list[dict[str, Any]]) -> None:
        (root / errors.CATALOG).write_bytes(
            plistlib.dumps({**header("ErrorCatalog"), "codes": codes})
        )

    def test_the_repository_is_current(self) -> None:
        self.assertEqual(errors.regenerate(ROOT, write=False), [])

    def test_the_endpoint_codes_are_in_order_(self) -> None:
        items = [
            item for item in errors.load_catalog(ROOT) if item["domain"] == "Endpoint"
        ]
        self.assertEqual(
            [(item["code"], item["name"]) for item in items],
            [
                ("E1001", "endpointDisabled"),
                ("E1002", "notGranted"),
                ("E1003", "invalidMessage"),
                ("E1004", "tooManyConnections"),
                ("E1005", "revoked"),
                ("E1006", "tooSlow"),
                ("E1007", "tooManyFeeds"),
                ("E1008", "feedClosed"),
                ("E1009", "unsupportedEndpointVersion"),
                ("E1010", "unexpectedKind"),
                ("E1011", "missingHeader"),
            ],
        )

    def test_a_code_with_the_wrong_prefix_for_its_domain_is_refused(self) -> None:
        with self.assertRaisesRegex(errors.ErrorCodeError, "E2001 is in the Endpoint"):
            errors.check_invariants([entry("E2001", "Endpoint", "wrongArea")])

    def test_the_document_area_holds_the_document_codes(self) -> None:
        documents = [
            (item["code"], item["name"])
            for item in errors.load_catalog(ROOT)
            if item["domain"] == "Document"
        ]
        self.assertEqual(
            documents,
            [
                ("E5001", "unsupportedAPIVersion"),
                ("E5002", "invalidProtocolDescription"),
                ("E5003", "protocolDescriptionFamilyMismatch"),
                ("E5004", "unknownProtocolVariant"),
                ("E5005", "damagedAccessGrants"),
                ("E5006", "damagedPortKey"),
                ("E5007", "invalidControllerRecord"),
                ("E5008", "sdlLineRejected"),
                ("E5009", "documentNotMigrated"),
                ("E5010", "invalidDocumentForm"),
            ],
        )
        with self.assertRaisesRegex(errors.ErrorCodeError, "E4001 is in the Document"):
            errors.check_invariants([entry("E4001", "Document", "wrongArea")])

    def test_a_repeated_code_or_name_is_refused(self) -> None:
        with self.assertRaisesRegex(errors.ErrorCodeError, "code E1001 is used twice"):
            errors.check_invariants(
                [entry("E1001", "Endpoint", "a"), entry("E1001", "Endpoint", "b")]
            )
        with self.assertRaisesRegex(errors.ErrorCodeError, "name same is used twice"):
            errors.check_invariants(
                [entry("E1001", "Endpoint", "same"), entry("E1002", "Endpoint", "same")]
            )

    def test_a_new_code_must_be_the_highest_code_of_its_area_plus_one(self) -> None:
        with self.assertRaisesRegex(errors.ErrorCodeError, "E1003 skips E1002"):
            errors.check_invariants(
                [entry("E1001", "Endpoint", "a"), entry("E1003", "Endpoint", "b")]
            )
        with self.assertRaisesRegex(errors.ErrorCodeError, "E2002 skips E2001"):
            errors.check_invariants([entry("E2002", "CLI", "a", exitCode=1)])

    def test_unsorted_entries_are_refused(self) -> None:
        with self.assertRaisesRegex(errors.ErrorCodeError, "not sorted"):
            errors.check_invariants(
                [entry("E1002", "Endpoint", "b"), entry("E1001", "Endpoint", "a")]
            )

    def test_each_domain_needs_its_own_fields(self) -> None:
        root = self.copy_repository()
        for item in (
            entry("E2001", "CLI", "noExit"),
            entry("E3001", "Remapping", "noWire"),
            entry("E1001", "Endpoint", "extraExit", exitCode=64),
            entry("E1001", "Endpoint", "extraField", extra="x"),
        ):
            with self.subTest(item=item["name"]):
                self.write_catalog(root, [item])
                with self.assertRaisesRegex(errors.ErrorCodeError, "breaks its schema"):
                    errors.load_catalog(root)

    def test_a_domain_in_the_earlier_spelling_is_refused(self) -> None:
        root = self.copy_repository()
        for domain in ("endpoint", "cli", "remapping", "mod", "document", "Cli"):
            with self.subTest(domain=domain):
                self.write_catalog(root, [entry("E1001", domain, "a")])
                with self.assertRaisesRegex(errors.ErrorCodeError, "breaks its schema"):
                    errors.load_catalog(root)

    def test_a_repeated_wire_value_is_refused(self) -> None:
        with self.assertRaisesRegex(
            errors.ErrorCodeError, "wire same_wire is used twice"
        ):
            errors.check_invariants(
                [
                    entry("E3001", "Remapping", "a", wire="same_wire"),
                    entry("E3002", "Remapping", "b", wire="same_wire"),
                ]
            )

    def test_a_cli_exit_code_must_be_a_documented_one(self) -> None:
        for exit_code in (2, 130):
            with (
                self.subTest(exit_code=exit_code),
                self.assertRaisesRegex(errors.ErrorCodeError, "does not document"),
            ):
                errors.check_invariants(
                    [entry("E2001", "CLI", "a", exitCode=exit_code)]
                )
        for exit_code in sorted(command_line_exit_statuses()):
            errors.check_invariants([entry("E2001", "CLI", "a", exitCode=exit_code)])

    def test_write_then_check_round_trips(self) -> None:
        root = self.copy_repository()
        catalog = errors.load_catalog(root)

        def next_code(prefix: str) -> str:
            count = sum(item["code"].startswith(prefix) for item in catalog)
            return f"{prefix}{count + 1:03d}"

        new_endpoint, new_cli, new_remapping = (
            next_code(prefix) for prefix in ("E1", "E2", "E3")
        )
        catalog.append(entry(new_endpoint, "Endpoint", "newCode"))
        catalog.append(entry(new_cli, "CLI", "newUsage", exitCode=64))
        catalog.append(
            entry(new_remapping, "Remapping", "otherWire", wire="other_wire")
        )
        self.write_catalog(root, sorted(catalog, key=lambda item: item["code"]))
        english = root / errors.ENGLISH_STRINGS
        english.write_text(
            english.read_text(encoding="utf-8")
            + f'"error.{new_endpoint}.message" = "A new code. Fix it.";\n'
            + f'"error.{new_cli}.message" = "Wrong usage. Read the help.";\n'
            + f'"error.{new_remapping}.message" = "Other wire. Fix it.";\n',
            encoding="utf-8",
        )
        self.assertEqual(
            errors.regenerate(root, write=False),
            [errors.ENDPOINT_SCHEMA, errors.WIKI_PAGE],
        )
        self.assertEqual(
            errors.regenerate(root, write=True),
            [errors.ENDPOINT_SCHEMA, errors.WIKI_PAGE],
        )
        self.assertEqual(errors.regenerate(root, write=False), [])
        schema = json.loads((root / errors.ENDPOINT_SCHEMA).read_text(encoding="utf-8"))
        enum = schema["$defs"]["error"]["properties"]["code"]["enum"]
        self.assertEqual(enum[-1], new_endpoint)
        page = (root / errors.WIKI_PAGE).read_text(encoding="utf-8")
        self.assertIn(f"| {new_endpoint} | Endpoint | A new code. Fix it. |", page)
        self.assertIn(
            f"| {new_cli} | Command line | Wrong usage. Read the help. Exit code 64. |",
            page,
        )
        self.assertIn(
            f"| {new_remapping} | Remapping | Other wire. Fix it. Wire value `other_wire`. |",
            page,
        )

    def test_escapes_in_the_english_text_are_decoded(self) -> None:
        root = self.copy_repository()
        (root / errors.ENGLISH_STRINGS).write_text(
            '"error.E1001.message" = "Run \\"ojd\\" in C:\\\\x.\\tNext.";\n',
            encoding="utf-8",
        )
        self.assertEqual(
            errors.english_strings(root),
            {"error.E1001.message": 'Run "ojd" in C:\\x.\tNext.'},
        )

    def test_only_the_error_definition_enum_is_rewritten(self) -> None:
        decoy = ["kept"]
        schema = {
            "properties": {"error": {"properties": {"code": {"enum": decoy}}}},
            "$defs": {"error": {"properties": {"code": {"enum": ["E1001"]}}}},
        }
        rendered = json.loads(
            errors.render_endpoint_schema(
                json.dumps(schema, indent="\t"),
                [entry("E1001", "Endpoint", "a"), entry("E1002", "Endpoint", "b")],
            )
        )
        self.assertEqual(
            rendered["properties"]["error"]["properties"]["code"]["enum"], decoy
        )
        self.assertEqual(
            rendered["$defs"]["error"]["properties"]["code"]["enum"], ["E1001", "E1002"]
        )

    def test_an_active_code_without_english_text_is_refused(self) -> None:
        root = self.copy_repository()
        self.write_catalog(root, [entry("E1001", "Endpoint", "a")])
        english = root / errors.ENGLISH_STRINGS
        english.write_text(
            "".join(
                line
                for line in english.read_text(encoding="utf-8").splitlines(
                    keepends=True
                )
                if not line.startswith('"error.E1001.message"')
            ),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(
            errors.ErrorCodeError, "no key error.E1001.message"
        ):
            errors.outputs(root)

    def test_a_hand_edited_wiki_table_is_stale(self) -> None:
        root = self.copy_repository()
        page = root / errors.WIKI_PAGE
        page.write_text(
            page.read_text(encoding="utf-8").replace("| E1001 |", "| E1001 edited |"),
            encoding="utf-8",
        )
        self.assertEqual(errors.regenerate(root, write=False), [errors.WIKI_PAGE])


if __name__ == "__main__":
    unittest.main()
