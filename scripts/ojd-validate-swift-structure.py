#!/usr/bin/env python3
# Validate durable Swift source and test layout constraints.

from __future__ import annotations

import argparse
from collections import defaultdict
from pathlib import Path
import re
import sys

MAX_LINES = 800
PREFERRED_LINES = 500
SWIFTLINT_DIRECTIVE = re.compile(r"swiftlint\s*:(?:disable|enable)")


def swift_files(root: Path) -> list[Path]:
    return sorted(
        path
        for tree in ("Sources", "Tests")
        for path in (root / tree).rglob("*.swift")
        if ".build" not in path.parts
    )


def validate(root: Path) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    notes: list[str] = []
    files = swift_files(root)

    for path in files:
        relative = path.relative_to(root)
        text = path.read_text(encoding="utf-8")
        line_count = len(text.splitlines())
        if line_count > MAX_LINES:
            errors.append(f"{relative}: {line_count} lines exceeds {MAX_LINES}")
        elif line_count > PREFERRED_LINES:
            notes.append(f"{relative}: {line_count} lines; consider a cohesive split")

        if "+" in path.name:
            errors.append(f"{relative}: use an ownership directory instead of a '+' filename")

        for line_number, line in enumerate(text.splitlines(), start=1):
            if SWIFTLINT_DIRECTIVE.search(line):
                errors.append(
                    f"{relative}:{line_number}: SwiftLint suppression directives are forbidden"
                )

    test_root = root / "Tests" / "OpenJoystickDriverKitTests"
    for path in sorted(test_root.glob("*.swift")):
        errors.append(f"{path.relative_to(root)}: tests must be placed by source ownership")

    target_roots = []
    for tree in ("Sources", "Tests"):
        tree_root = root / tree
        if tree_root.is_dir():
            target_roots.extend(path for path in tree_root.iterdir() if path.is_dir())
    for target_root in target_roots:
        by_name: dict[str, list[Path]] = defaultdict(list)
        for path in target_root.rglob("*.swift"):
            by_name[path.name].append(path)
        for name, matches in sorted(by_name.items()):
            if len(matches) > 1:
                joined = ", ".join(str(path.relative_to(root)) for path in matches)
                errors.append(
                    f"{target_root.relative_to(root)}: duplicate Swift basename {name}: {joined}"
                )

    return errors, notes


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="repository root (defaults to the script's parent repository)",
    )
    args = parser.parse_args()
    errors, notes = validate(args.root.resolve())

    for note in notes:
        print(f"note: {note}")
    for error in errors:
        print(f"error: {error}", file=sys.stderr)

    if errors:
        print(f"Swift structure validation failed with {len(errors)} error(s).", file=sys.stderr)
        return 1

    print("Swift structure validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
