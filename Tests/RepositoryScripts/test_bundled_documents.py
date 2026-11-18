"""Every bundled document is a property list in the canonical form that `DocumentCoder` writes."""

from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from Scripts.Quality import repository_tool

ROOT = Path(__file__).resolve().parents[2]
# The folders and files that hold bundled documents (files with `apiVersion` and `kind`).
# `Schemas/` holds the JSON Schema contracts and `Localization/` holds string tables, not documents.
FOLDERS = (
    "Resources/CatalogRules",
    "Resources/ControllerPatches",
    "Resources/Controllers",
    "Resources/Protocols",
    "Resources/VirtualDevices",
    "Resources/Vocabulary",
    "Sources/OpenJoystickDriverKit/Resources/Controllers",
    "Sources/OpenJoystickDriverKit/Resources/Protocols",
    "Sources/OpenJoystickDriverKit/Resources/VirtualDevices",
)
FILES = ("Resources/ErrorCodes.plist",)


def bundled_files() -> list[Path]:
    """Every file under the bundled document folders, plus the single bundled files."""
    found = [ROOT / name for name in FILES]
    for folder in FOLDERS:
        found.extend(
            path for path in sorted((ROOT / folder).rglob("*")) if path.is_file()
        )
    return found


class BundledDocumentTests(unittest.TestCase):
    def test_no_bundled_document_is_a_json_file(self) -> None:
        stray = [
            str(path.relative_to(ROOT))
            for path in bundled_files()
            if path.suffix != ".plist"
        ]
        self.assertEqual([], stray)
        self.assertFalse((ROOT / "Resources/ErrorCodes.json").exists())

    def test_every_bundled_document_equals_its_canonical_form(self) -> None:
        files = [path for path in bundled_files() if path.suffix == ".plist"]
        self.assertTrue(files)
        with tempfile.TemporaryDirectory() as directory:
            copies = []
            for index, path in enumerate(files):
                copy = Path(directory) / f"{index}.plist"
                shutil.copyfile(path, copy)
                copies.append(copy)
            # format-plist writes the form DocumentCoder writes; a file that differs is not canonical.
            subprocess.run(
                [str(repository_tool.binary()), "format-plist", *map(str, copies)],
                check=True,
                capture_output=True,
                text=True,
            )
            differing = [
                str(path.relative_to(ROOT))
                for path, copy in zip(files, copies, strict=True)
                if path.read_bytes() != copy.read_bytes()
            ]
        self.assertEqual([], differing)


if __name__ == "__main__":
    unittest.main()
