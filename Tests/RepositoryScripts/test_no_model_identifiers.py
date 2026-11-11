from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "Sources"
ALLOW_LIST = Path(__file__).with_name("model_identifiers_allowed.json")

HEX = r"0x[0-9A-Fa-f]{4}\b"
VENDOR = re.compile(rf"[Vv]endor\w*[^\n]{{1,24}}?{HEX}")
PRODUCT_NAME = re.compile(r"[Pp]roduct")
LITERAL = re.compile(HEX)
# A product literal may sit on the line after its name, as in a list of product IDs.
PRODUCT_REACH = 2
VENDOR_REACH = 6


def pairs(path: Path) -> list[int]:
    """The 1-based lines of `path` that hold a vendor literal with a product literal near it."""
    lines = path.read_text(encoding="utf-8").splitlines()
    found: list[int] = []
    for index, line in enumerate(lines):
        if not VENDOR.search(line):
            continue
        window = lines[index : index + VENDOR_REACH]
        for offset, candidate in enumerate(window):
            if not PRODUCT_NAME.search(candidate):
                continue
            reach = lines[index + offset : index + offset + PRODUCT_REACH + 1]
            literals = [match for text in reach for match in LITERAL.findall(text)]
            product_here = re.search(rf"[Pp]roduct\w*\W{{1,12}}{HEX}", candidate)
            if product_here or (literals and candidate is not line):
                found.append(index + 1)
                break
    return found


def allowed() -> dict[str, str]:
    entries = json.loads(ALLOW_LIST.read_text(encoding="utf-8"))
    result: dict[str, str] = {}
    for entry in entries:
        reason = entry.get("reason", "")
        if not reason.strip():
            raise AssertionError(f"allow-list entry {entry.get('path')} has no reason")
        result[entry["path"]] = reason
    return result


class NoModelIdentifierTests(unittest.TestCase):
    def test_a_literal_vendor_and_product_pair_is_listed_with_a_reason(self) -> None:
        listed = allowed()
        unlisted: list[str] = []
        for path in sorted(SOURCES.rglob("*.swift")):
            relative = path.relative_to(ROOT).as_posix()
            if relative in listed:
                continue
            for line in pairs(path):
                unlisted.append(f"{relative}:{line}")
        self.assertEqual(
            unlisted,
            [],
            "move the fact into a record, key it by family, or list the file in "
            f"{ALLOW_LIST.name} with a reason",
        )

    def test_every_allow_list_entry_still_names_a_file_with_a_pair(self) -> None:
        stale = [
            path
            for path in allowed()
            if not (ROOT / path).is_file() or not pairs(ROOT / path)
        ]
        self.assertEqual(stale, [], "remove the entry that no longer matches")

    def test_the_detector_reports_a_pair_and_a_product_list(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as directory:
            sample = Path(directory) / "Sample.swift"
            sample.write_text(
                "let a = vendorID == 0x057E && productID == 0x2009\n"
                "let vendorID: UInt16 = 0x045E\n"
                "let productIDs: [UInt16] = [\n"
                "  0x02D1,\n"
                "]\n"
                "let only = vendorID == 0x057E\n",
                encoding="utf-8",
            )
            self.assertEqual(pairs(sample), [1, 2])


if __name__ == "__main__":
    unittest.main()
