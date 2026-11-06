"""Fail when a file under a code tree carries a GPL-family license identifier or license text.

OpenJoystickDriver takes code only from MIT, BSD, zlib, CC0 or Apache-2.0 sources. GPL, LGPL
and AGPL sources give facts only, so their identifiers and license text never appear in
`Sources`, `Tests`, `Tools`, `Resources` or `Scripts`. Documentation may cite such sources, so
`docs/` and `wiki/` are not scanned. This script and its test name the pattern they look for,
so both are skipped by path. Files that are not UTF-8 text, such as images, hold no license
header and are skipped.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys
from collections.abc import Iterable, Iterator

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCANNED = ("Sources", "Tests", "Tools", "Resources", "Scripts")
SKIPPED = frozenset(
    {
        "Scripts/Quality/check_license_headers.py",
        "Tests/RepositoryScripts/test_license_headers.py",
    }
)
GPL_FAMILY = re.compile(
    r"\b[AL]?GPL\b|GNU\s+(?:Lesser\s+|Library\s+|Affero\s+)?General\s+Public\s+License",
    re.IGNORECASE,
)


def files(root: pathlib.Path) -> Iterator[pathlib.Path]:
    for tree in SCANNED:
        for path in sorted((root / tree).rglob("*")):
            if path.is_file() and path.relative_to(root).as_posix() not in SKIPPED:
                yield path


def violations(root: pathlib.Path = ROOT) -> list[str]:
    found = []
    for path in files(root):
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for number, line in enumerate(text.splitlines(), start=1):
            if GPL_FAMILY.search(line):
                found.append(f"{path.relative_to(root).as_posix()}:{number}: {line.strip()}")
    return found


def main(arguments: Iterable[str] = ()) -> int:
    argparse.ArgumentParser(
        description="Fail when a code tree carries a GPL-family license identifier or text."
    ).parse_args(list(arguments))
    found = violations()
    for entry in found:
        print(f"GPL-family license text in a code tree: {entry}", file=sys.stderr)
    return 1 if found else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
