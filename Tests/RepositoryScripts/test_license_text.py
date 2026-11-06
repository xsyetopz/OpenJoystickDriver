from __future__ import annotations

import shutil
import tempfile
import unittest
from pathlib import Path

from Scripts.Quality import check_license_text as check

NOTICE = "Required Notice: Copyright (c) 2026 Krystian J."


class LicenseTextTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        pinned = self.root / check.PINNED
        pinned.parent.mkdir(parents=True)
        shutil.copyfile(check.ROOT / check.PINNED, pinned)
        self.text = pinned.read_text(encoding="utf-8")

    def tearDown(self) -> None:
        self.directory.cleanup()

    def write_license(self, text: str) -> None:
        (self.root / check.LICENSE).write_text(text, encoding="utf-8")

    def test_verbatim_text_with_notice_passes(self) -> None:
        self.write_license(f"{self.text}\n{NOTICE}\n")
        self.assertEqual(check.problems(self.root), [])

    def test_one_word_edit_names_the_line(self) -> None:
        self.write_license(
            f"{self.text.replace('strict obligations', 'loose obligations')}\n{NOTICE}\n"
        )
        [problem] = check.problems(self.root)
        self.assertIn("at line 7", problem)

    def test_missing_notice_fails(self) -> None:
        self.write_license(self.text)
        [problem] = check.problems(self.root)
        self.assertIn("Required Notice:", problem)

    def test_truncated_text_fails(self) -> None:
        self.write_license(f"{self.text.splitlines()[0]}\n{NOTICE}\n")
        [problem] = check.problems(self.root)
        self.assertIn("license lines", problem)

    def test_mit_text_fails(self) -> None:
        self.write_license(f"MIT License\n\n{NOTICE}\n")
        self.assertEqual(len(check.problems(self.root)), 1)

    def test_edited_pinned_copy_fails(self) -> None:
        (self.root / check.PINNED).write_text(self.text + "extra\n", encoding="utf-8")
        self.write_license(f"{self.text}\n{NOTICE}\n")
        [problem] = check.problems(self.root)
        self.assertIn("SHA-256", problem)


if __name__ == "__main__":
    unittest.main()
