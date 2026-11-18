from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VIEWS = Path("Sources/OpenJoystickDriverPresentation")
POINT_SIZE = re.compile(
    r"\.system\(\s*size\s*:|\.custom\([^)]*\bsize\s*:|systemFont\(\s*ofSize\s*:"
)
CAPTION = re.compile(r"\.caption[12]?\b")
SECONDARY = re.compile(r"secondaryLabelColor|tertiaryLabelColor|\.secondary\b")
WINDOW = 3


def findings(source: str) -> list[tuple[int, str]]:
    lines = [line.split("//", 1)[0] for line in source.splitlines()]
    found: list[tuple[int, str]] = []
    for index, line in enumerate(lines):
        if POINT_SIZE.search(line):
            found.append((index + 1, "font set by point size"))
        if CAPTION.search(line) and not SECONDARY.search(
            " ".join(lines[index : index + WINDOW])
        ):
            found.append((index + 1, "caption on text that is not secondary"))
    return found


def scan(root: Path) -> list[str]:
    report: list[str] = []
    for path in sorted((root / VIEWS).rglob("*.swift")):
        relative = path.relative_to(root)
        for line, reason in findings(path.read_text(encoding="utf-8")):
            report.append(f"{relative}:{line}: {reason}")
    return report


def main(arguments: list[str] | None = None) -> int:
    if arguments:
        print("usage: check_text_styles.py", file=sys.stderr)
        return 2
    report = scan(ROOT)
    for entry in report:
        print(entry)
    if report:
        print(f"error: {len(report)} text style violation(s)", file=sys.stderr)
        return 1
    print(
        "Every text under Sources/OpenJoystickDriverPresentation uses a system text style."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
