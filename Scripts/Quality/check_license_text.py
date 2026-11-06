"""Fail when `LICENSE` differs from the pinned PolyForm Noncommercial License 1.0.0 text.

`LICENSE` holds the license verbatim followed by `Required Notice:` lines that name the
copyright holder. The comparison drops lines that begin with `Required Notice:`, as the license
itself defines them, and names the first line that differs. The pinned copy comes from tag
`1.0.0` of https://github.com/polyformproject/polyform-licenses, and its SHA-256 is checked so
an edit to the pinned copy fails too.
"""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import sys
from collections.abc import Iterable

ROOT = pathlib.Path(__file__).resolve().parents[2]
LICENSE = "LICENSE"
PINNED = "Resources/Licenses/polyform-noncommercial-1.0.0.txt"
PINNED_SHA256 = "c0ea4a896d2c8c394b29f9427589996db826cd501c512279ff0ed3ef48fabbe5"
NOTICE = "Required Notice:"


def problems(root: pathlib.Path = ROOT) -> list[str]:
    pinned = (root / PINNED).read_bytes()
    if hashlib.sha256(pinned).hexdigest() != PINNED_SHA256:
        return [f"{PINNED} does not match its recorded SHA-256 {PINNED_SHA256}"]
    license_lines = (root / LICENSE).read_text(encoding="utf-8").splitlines()
    if not any(line.startswith(NOTICE) for line in license_lines):
        return [f"{LICENSE} has no line that begins with {NOTICE!r}"]
    expected = pinned.decode("utf-8").splitlines()
    actual = [line for line in license_lines if not line.startswith(NOTICE)]
    while actual and not actual[-1]:
        actual.pop()
    for number, (want, got) in enumerate(zip(expected, actual, strict=False), start=1):
        if want != got:
            return [f"{LICENSE} differs from {PINNED} at line {number}: {got!r} != {want!r}"]
    if len(actual) != len(expected):
        return [f"{LICENSE} has {len(actual)} license lines; {PINNED} has {len(expected)}"]
    return []


def main(arguments: Iterable[str] = ()) -> int:
    argparse.ArgumentParser(
        description="Fail when LICENSE differs from the pinned PolyForm Noncommercial text."
    ).parse_args(list(arguments))
    found = problems()
    for entry in found:
        print(entry, file=sys.stderr)
    return 1 if found else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
