from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from Scripts.Quality import check_license_headers as check


def write(root: Path, relative: str, text: str) -> None:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class LicenseHeaderTests(unittest.TestCase):
    def test_spdx_line_under_sources_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(
                root,
                "Sources/Kit/Driver.swift",
                "// SPDX-License-Identifier: GPL-2.0-or-later\nimport Foundation\n",
            )
            self.assertEqual(
                check.violations(root),
                [
                    "Sources/Kit/Driver.swift:1: "
                    "// SPDX-License-Identifier: GPL-2.0-or-later"
                ],
            )

    def test_license_text_under_scripts_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(
                root,
                "Scripts/tool.py",
                "# This program is free software; see the\n"
                "# GNU General Public License for more details.\n",
            )
            self.assertEqual(
                check.violations(root),
                ["Scripts/tool.py:2: # GNU General Public License for more details."],
            )

    def test_reference_under_docs_passes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(root, "docs/sources.md", "Linux `xpad.c` is GPL-2.0; facts only.\n")
            write(root, "Sources/Kit/Driver.swift", "import Foundation\n")
            self.assertEqual(check.violations(root), [])

    def test_word_containing_the_letters_passes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(root, "Resources/notes.txt", "GPLAYER and LGPLX are not license names.\n")
            self.assertEqual(check.violations(root), [])


if __name__ == "__main__":
    unittest.main()
