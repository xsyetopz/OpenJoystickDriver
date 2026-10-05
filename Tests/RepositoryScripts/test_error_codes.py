from __future__ import annotations

import json
import shutil
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

from Scripts.Catalog import generate_error_codes as errors

ROOT = Path(__file__).resolve().parents[2]
COPIED = (
    errors.CATALOG,
    errors.CATALOG_SCHEMA,
    errors.ENDPOINT_SCHEMA,
    errors.WIKI_PAGE,
    errors.TEMPLATE,
)


def entry(code: str, domain: str, name: str, **extra: Any) -> dict[str, Any]:
    return {"code": code, "domain": domain, "name": name, "status": "active", **extra}


class ErrorCodeTests(unittest.TestCase):
    def copy_repository(self) -> Path:
        directory = Path(tempfile.mkdtemp(prefix="ojd-errors-"))
        self.addCleanup(shutil.rmtree, directory)
        for path in COPIED:
            (directory / path).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(ROOT / path, directory / path)
        return directory

    def write_catalog(self, root: Path, codes: list[dict[str, Any]]) -> None:
        (root / errors.CATALOG).write_text(
            json.dumps({"codes": codes}), encoding="utf-8"
        )

    def test_the_repository_is_current(self) -> None:
        self.assertEqual(errors.regenerate(ROOT, write=False), [])

    def test_the_endpoint_codes_are_the_nine_codes_in_order(self) -> None:
        names = [
            item["name"]
            for item in errors.load_catalog(ROOT)
            if item["domain"] == "endpoint"
        ]
        self.assertEqual(
            names,
            [
                "endpointDisabled",
                "notGranted",
                "unsupportedProtocol",
                "invalidMessage",
                "tooManyConnections",
                "revoked",
                "tooSlow",
                "tooManyFeeds",
                "feedClosed",
            ],
        )

    def test_a_code_with_the_wrong_prefix_for_its_domain_is_refused(self) -> None:
        with self.assertRaisesRegex(errors.ErrorCodeError, "E2001 is in the endpoint"):
            errors.check_invariants([entry("E2001", "endpoint", "wrongArea")])

    def test_a_repeated_code_or_name_is_refused(self) -> None:
        with self.assertRaisesRegex(errors.ErrorCodeError, "code E1001 is used twice"):
            errors.check_invariants(
                [entry("E1001", "endpoint", "a"), entry("E1001", "endpoint", "b")]
            )
        with self.assertRaisesRegex(errors.ErrorCodeError, "name same is used twice"):
            errors.check_invariants(
                [entry("E1001", "endpoint", "same"), entry("E1002", "endpoint", "same")]
            )

    def test_unsorted_entries_are_refused(self) -> None:
        with self.assertRaisesRegex(errors.ErrorCodeError, "not sorted"):
            errors.check_invariants(
                [entry("E1002", "endpoint", "b"), entry("E1001", "endpoint", "a")]
            )

    def test_each_domain_needs_its_own_fields(self) -> None:
        root = self.copy_repository()
        for item in (
            entry("E2001", "cli", "noExit"),
            entry("E3001", "remapping", "noWire"),
            entry("E1001", "endpoint", "extraExit", exitCode=64),
            {**entry("E1001", "endpoint", "noVersion"), "status": "retired"},
            entry("E1001", "endpoint", "extraVersion", retiredIn="0.5.0"),
        ):
            with self.subTest(item=item["name"]):
                self.write_catalog(root, [item])
                with self.assertRaisesRegex(errors.ErrorCodeError, "breaks its schema"):
                    errors.load_catalog(root)

    # The previous catalogs below are fakes: they stand for the catalog at a release tag.
    def test_a_deleted_released_code_is_refused(self) -> None:
        fake_previous = [
            entry("E1001", "endpoint", "a"),
            entry("E1002", "endpoint", "b"),
        ]
        with self.assertRaisesRegex(errors.ErrorCodeError, "E1002 .* was deleted"):
            errors.check_not_reused(fake_previous, [entry("E1001", "endpoint", "a")])

    def test_a_released_code_given_another_meaning_is_refused(self) -> None:
        fake_previous = [entry("E1001", "endpoint", "a")]
        with self.assertRaisesRegex(errors.ErrorCodeError, "never reused"):
            errors.check_not_reused(
                fake_previous, [entry("E1001", "endpoint", "other")]
            )
        with self.assertRaisesRegex(errors.ErrorCodeError, "never reused"):
            errors.check_not_reused(
                fake_previous, [entry("E1001", "cli", "a", exitCode=1)]
            )

    def test_a_retired_or_new_code_passes_the_reuse_guard(self) -> None:
        fake_previous = [entry("E1001", "endpoint", "a")]
        retired = {**entry("E1001", "endpoint", "a"), "status": "retired"}
        errors.check_not_reused(
            fake_previous, [retired, entry("E1002", "endpoint", "b")]
        )

    def test_the_guard_runs_against_the_released_catalog(self) -> None:
        root = self.copy_repository()
        fake_previous = ("0.0.0", [entry("E1999", "endpoint", "gone")])
        with (
            patch.object(errors, "released_catalog", return_value=fake_previous),
            self.assertRaisesRegex(errors.ErrorCodeError, "compared with 0.0.0"),
        ):
            errors.outputs(root)

    def test_write_then_check_round_trips(self) -> None:
        root = self.copy_repository()
        catalog = errors.load_catalog(root)
        catalog.append(entry("E1010", "endpoint", "newCode"))
        catalog.append(entry("E2001", "cli", "usage", exitCode=64))
        catalog.append(
            {
                **entry("E3001", "remapping", "oldWire", wire="old_wire"),
                "status": "retired",
                "retiredIn": "0.5.0",
            }
        )
        self.write_catalog(root, catalog)
        template = root / errors.TEMPLATE
        template.write_text(
            template.read_text(encoding="utf-8")
            + '"error.E1010" = "A new code. Fix it.";\n'
            + '"error.E2001" = "Wrong usage. Read the help.";\n',
            encoding="utf-8",
        )
        with patch.object(errors, "released_catalog", return_value=None):
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
        self.assertEqual(enum[-2:], ["E1009", "E1010"])
        page = (root / errors.WIKI_PAGE).read_text(encoding="utf-8")
        self.assertIn("| E1010 | Endpoint | A new code. Fix it. |", page)
        self.assertIn(
            "| E2001 | Command line | Wrong usage. Read the help. Exit code 64. |", page
        )
        self.assertIn("| E3001 | Remapping | Retired in 0.5.0. |", page)

    def test_an_active_code_without_english_text_is_refused(self) -> None:
        root = self.copy_repository()
        self.write_catalog(
            root, [entry("E1001", "endpoint", "a"), entry("E1099", "endpoint", "b")]
        )
        with (
            patch.object(errors, "released_catalog", return_value=None),
            self.assertRaisesRegex(errors.ErrorCodeError, "no key error.E1099"),
        ):
            errors.outputs(root)

    def test_a_hand_edited_wiki_table_is_stale(self) -> None:
        root = self.copy_repository()
        page = root / errors.WIKI_PAGE
        page.write_text(
            page.read_text(encoding="utf-8").replace("| E1001 |", "| E1001 edited |"),
            encoding="utf-8",
        )
        with patch.object(errors, "released_catalog", return_value=None):
            self.assertEqual(errors.regenerate(root, write=False), [errors.WIKI_PAGE])


if __name__ == "__main__":
    unittest.main()
