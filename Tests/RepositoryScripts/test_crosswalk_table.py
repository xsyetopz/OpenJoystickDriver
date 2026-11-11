from __future__ import annotations

import copy
import plistlib
import shutil
import tempfile
import unittest
from collections.abc import Callable
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator

from Scripts.Catalog import generate_crosswalk as crosswalk
from Scripts.Quality import validate_schemas

ROOT = Path(__file__).resolve().parents[2]
COPIED = (crosswalk.CROSSWALK, crosswalk.WIKI_PAGE)


class CrosswalkTableTests(unittest.TestCase):
    def copy_repository(self) -> Path:
        directory = Path(tempfile.mkdtemp(prefix="ojd-crosswalk-"))
        self.addCleanup(shutil.rmtree, directory)
        for path in COPIED:
            (directory / path).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(ROOT / path, directory / path)
        return directory

    def edit_crosswalk(
        self, root: Path, control: str, column: str, value: object
    ) -> None:
        path = root / crosswalk.CROSSWALK
        document = plistlib.loads(path.read_bytes())
        document["controls"][control][column] = value
        path.write_bytes(plistlib.dumps(document))

    def test_the_wiki_table_matches_the_plist(self) -> None:
        self.assertEqual(crosswalk.regenerate(ROOT, write=False), [])

    def test_the_table_has_a_row_per_control_and_a_source_per_column(self) -> None:
        page = (ROOT / crosswalk.WIKI_PAGE).read_text(encoding="utf-8")
        document = plistlib.loads((ROOT / crosswalk.CROSSWALK).read_bytes())
        for control in document["controls"]:
            self.assertIn(f"| `{control}` |", page)
        for column in document["sources"].values():
            self.assertIn(column["url"], page)

    def test_an_absent_key_is_a_dash_and_an_absent_usage_is_the_device(self) -> None:
        root = self.copy_repository()
        path = root / crosswalk.CROSSWALK
        document = plistlib.loads(path.read_bytes())
        row = document["controls"]["South"]
        del row["sdl"]
        row["hid"] = [{"page": "Button"}]
        path.write_bytes(plistlib.dumps(document))
        cells = crosswalk.wiki_block(crosswalk.load(root)).splitlines()
        south = next(line for line in cells if line.startswith("| `South` |"))
        self.assertIn("| - |", south)
        self.assertIn("`Button:device`", south)

    def test_a_changed_plist_cell_makes_the_wiki_stale(self) -> None:
        root = self.copy_repository()
        self.edit_crosswalk(root, "South", "sdl", "NOT_SOUTH")
        self.assertEqual(crosswalk.regenerate(root, write=False), [crosswalk.WIKI_PAGE])
        self.assertEqual(crosswalk.regenerate(root, write=True), [crosswalk.WIKI_PAGE])
        self.assertEqual(crosswalk.regenerate(root, write=False), [])
        self.assertIn(
            "`NOT_SOUTH`", (root / crosswalk.WIKI_PAGE).read_text(encoding="utf-8")
        )

    def test_a_changed_wiki_cell_is_found(self) -> None:
        root = self.copy_repository()
        page = root / crosswalk.WIKI_PAGE
        text = page.read_text(encoding="utf-8")
        page.write_text(text.replace("`BTN_SOUTH`", "`BTN_A`", 1), encoding="utf-8")
        self.assertEqual(crosswalk.regenerate(root, write=False), [crosswalk.WIKI_PAGE])

    def test_a_page_without_the_markers_is_refused(self) -> None:
        root = self.copy_repository()
        page = root / crosswalk.WIKI_PAGE
        page.write_text(
            page.read_text(encoding="utf-8").replace(crosswalk.BEGIN, ""),
            encoding="utf-8",
        )
        with self.assertRaises(crosswalk.CrosswalkError):
            crosswalk.regenerate(root, write=False)

    def test_a_column_without_a_source_is_refused(self) -> None:
        root = self.copy_repository()
        path = root / crosswalk.CROSSWALK
        document = plistlib.loads(path.read_bytes())
        del document["sources"]["apple"]
        path.write_bytes(plistlib.dumps(document))
        with self.assertRaises(crosswalk.CrosswalkError):
            crosswalk.regenerate(root, write=False)


class CrosswalkSchemaTests(unittest.TestCase):
    def setUp(self) -> None:
        documents = validate_schemas.validate_schema_documents()
        registry = validate_schemas.schema_registry(documents)
        self.validator = Draft202012Validator(
            documents["crosswalk.schema.json"], registry=registry
        )
        self.document: dict[str, Any] = plistlib.loads(
            (ROOT / crosswalk.CROSSWALK).read_bytes()
        )

    def rejects(self, edit: Callable[[dict[str, Any]], None]) -> bool:
        planted = copy.deepcopy(self.document)
        edit(planted)
        return not self.validator.is_valid(planted)

    def test_the_crosswalk_matches_its_schema(self) -> None:
        self.assertEqual(list(self.validator.iter_errors(self.document)), [])

    def test_an_absent_key_is_accepted(self) -> None:
        planted = copy.deepcopy(self.document)
        del planted["controls"]["South"]["evdev"]
        del planted["controls"]["South"]["hid"][0]["usage"]
        self.assertEqual(list(self.validator.iter_errors(planted)), [])

    def test_planted_bad_files_are_rejected(self) -> None:
        def unknown_member(d: dict[str, Any]) -> None:
            d["extra"] = True

        def wrong_kind(d: dict[str, Any]) -> None:
            d["kind"] = "Other"

        def missing_source(d: dict[str, Any]) -> None:
            del d["sources"]["apple"]

        def undated_source(d: dict[str, Any]) -> None:
            del d["sources"]["sdl"]["checkedOn"]

        def missing_pages(d: dict[str, Any]) -> None:
            del d["sources"]["hid"]["pages"]

        def unknown_control(d: dict[str, Any]) -> None:
            d["controls"]["Cross"] = d["controls"]["South"]

        def unknown_column(d: dict[str, Any]) -> None:
            d["controls"]["South"]["gcc"] = "ButtonA"

        def null_column(d: dict[str, Any]) -> None:
            d["controls"]["South"]["evdev"] = None

        def null_usage(d: dict[str, Any]) -> None:
            d["controls"]["South"]["hid"][0]["usage"] = None

        def empty_hid(d: dict[str, Any]) -> None:
            d["controls"]["South"]["hid"] = []

        for edit in (
            unknown_member,
            wrong_kind,
            missing_source,
            undated_source,
            missing_pages,
            unknown_control,
            unknown_column,
            null_column,
            null_usage,
            empty_hid,
        ):
            with self.subTest(edit.__name__):
                self.assertTrue(self.rejects(edit))


if __name__ == "__main__":
    unittest.main()
