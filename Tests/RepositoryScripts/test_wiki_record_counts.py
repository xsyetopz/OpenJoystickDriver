from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RECORDS = ROOT / "Sources/OpenJoystickDriverKit/Resources/Controllers"
STATED_COUNT = re.compile(
    r"\bcatalog (?:has|of|holds|includes|contains) (\d[\d,]*) (?:controller )?records\b"
)


class WikiRecordCountTests(unittest.TestCase):
    def test_every_stated_count_of_bundled_records_matches_the_generated_set(
        self,
    ) -> None:
        generated = len(list(RECORDS.glob("*/*.plist")))
        self.assertGreater(generated, 0)
        stated = [
            (page.name, number, int(number.replace(",", "")))
            for page in sorted((ROOT / "wiki").glob("*.md"))
            for line in page.read_text(encoding="utf-8").splitlines()
            for number in STATED_COUNT.findall(line)
        ]
        self.assertTrue(stated, "no wiki page states a count of records")
        for page, text, value in stated:
            with self.subTest(page=page, stated=text):
                self.assertEqual(
                    value, generated, f"{page} states {text} records, not {generated}"
                )


if __name__ == "__main__":
    unittest.main()
