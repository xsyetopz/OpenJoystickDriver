from __future__ import annotations

import json
import shutil
import subprocess
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

    def test_a_new_code_must_be_the_highest_code_of_its_area_plus_one(self) -> None:
        with self.assertRaisesRegex(errors.ErrorCodeError, "E1003 skips E1002"):
            errors.check_invariants(
                [entry("E1001", "endpoint", "a"), entry("E1003", "endpoint", "b")]
            )
        with self.assertRaisesRegex(errors.ErrorCodeError, "E2002 skips E2001"):
            errors.check_invariants([entry("E2002", "cli", "a", exitCode=1)])

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

    def test_a_repeated_wire_value_is_refused(self) -> None:
        with self.assertRaisesRegex(
            errors.ErrorCodeError, "wire same_wire is used twice"
        ):
            errors.check_invariants(
                [
                    entry("E3001", "remapping", "a", wire="same_wire"),
                    entry("E3002", "remapping", "b", wire="same_wire"),
                ]
            )

    def test_a_cli_exit_code_must_be_a_documented_one(self) -> None:
        for exit_code in (2, 130):
            with (
                self.subTest(exit_code=exit_code),
                self.assertRaisesRegex(errors.ErrorCodeError, "does not document"),
            ):
                errors.check_invariants(
                    [entry("E2001", "cli", "a", exitCode=exit_code)]
                )
        for exit_code in sorted(errors.CLI_EXIT_CODES):
            errors.check_invariants([entry("E2001", "cli", "a", exitCode=exit_code)])

    def test_every_cli_exit_code_is_documented_in_the_command_line_page(self) -> None:
        page = (ROOT / "wiki/Command-Line.md").read_text(encoding="utf-8")
        for exit_code in sorted(errors.CLI_EXIT_CODES):
            self.assertRegex(page, rf"\| {exit_code} \|")

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

    def test_the_released_catalog_is_read_at_the_last_tag_before_head(self) -> None:
        root = Path(tempfile.mkdtemp(prefix="ojd-errors-git-"))
        self.addCleanup(shutil.rmtree, root)

        def run_git(*args: str) -> None:
            subprocess.run(
                [
                    "git",
                    "-c",
                    "user.name=test",
                    "-c",
                    "user.email=test@example.invalid",
                    "-c",
                    "commit.gpgsign=false",
                    "-c",
                    "tag.gpgsign=false",
                    *args,
                ],
                cwd=root,
                check=True,
                capture_output=True,
            )

        run_git("init", "-q")
        self.assertIsNone(errors.released_catalog(root))
        (root / errors.CATALOG).parent.mkdir(parents=True)
        released = [entry("E1001", "endpoint", "a")]
        self.write_catalog(root, released)
        run_git("add", "-A")
        run_git("commit", "-q", "-m", "release")
        run_git("tag", "0.4.0")
        self.write_catalog(root, [*released, entry("E1002", "endpoint", "b")])
        run_git("commit", "-q", "-am", "next")

        self.assertEqual(errors.released_catalog(root), ("0.4.0", released))

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

        def next_code(prefix: str) -> str:
            count = sum(item["code"].startswith(prefix) for item in catalog)
            return f"{prefix}{count + 1:03d}"

        new_endpoint, new_cli, new_remapping = (
            next_code(prefix) for prefix in ("E1", "E2", "E3")
        )
        catalog.append(entry(new_endpoint, "endpoint", "newCode"))
        catalog.append(entry(new_cli, "cli", "newUsage", exitCode=64))
        catalog.append(
            {
                **entry(new_remapping, "remapping", "oldWire", wire="old_wire"),
                "status": "retired",
                "retiredIn": "0.5.0",
            }
        )
        self.write_catalog(root, sorted(catalog, key=lambda item: item["code"]))
        template = root / errors.TEMPLATE
        template.write_text(
            template.read_text(encoding="utf-8")
            + f'"error.{new_endpoint}" = "A new code. Fix it.";\n'
            + f'"error.{new_cli}" = "Wrong usage. Read the help.";\n',
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
        self.assertEqual(enum[-1], new_endpoint)
        page = (root / errors.WIKI_PAGE).read_text(encoding="utf-8")
        self.assertIn(f"| {new_endpoint} | Endpoint | A new code. Fix it. |", page)
        self.assertIn(
            f"| {new_cli} | Command line | Wrong usage. Read the help. Exit code 64. |",
            page,
        )
        self.assertIn(f"| {new_remapping} | Remapping | Retired in 0.5.0. |", page)

    def test_escapes_in_the_english_text_are_decoded(self) -> None:
        root = self.copy_repository()
        (root / errors.TEMPLATE).write_text(
            '"error.E1001" = "Run \\"ojd\\" in C:\\\\x.\\tNext.";\n', encoding="utf-8"
        )
        self.assertEqual(
            errors.english_strings(root), {"error.E1001": 'Run "ojd" in C:\\x.\tNext.'}
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
                [entry("E1001", "endpoint", "a"), entry("E1002", "endpoint", "b")],
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
        self.write_catalog(root, [entry("E1001", "endpoint", "a")])
        template = root / errors.TEMPLATE
        template.write_text(
            "".join(
                line
                for line in template.read_text(encoding="utf-8").splitlines(
                    keepends=True
                )
                if not line.startswith('"error.E1001"')
            ),
            encoding="utf-8",
        )
        with (
            patch.object(errors, "released_catalog", return_value=None),
            self.assertRaisesRegex(errors.ErrorCodeError, "no key error.E1001"),
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
