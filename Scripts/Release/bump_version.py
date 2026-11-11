from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import NoReturn

from .bundle_version import release_version

ROOT = Path(__file__).resolve().parents[2]


def die(message: str) -> NoReturn:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(2)


class MissingReference(Exception): ...


def replace_once(
    path: Path, pattern: re.Pattern[str], replacement: str, description: str
) -> str:
    text = path.read_text()
    updated, count = pattern.subn(replacement, text, count=1)
    if count != 1:
        raise MissingReference(f"{path}: {description}")
    return updated


def main(argv: list[str]) -> int:
    version = argv[0] if argv else ""
    if not version:
        die("usage: just release-bump-version <version>")
    if len(argv) != 1:
        die("Version must be SemVer, for example 0.1.0-rc.2")
    release_version(version)

    app_info = ROOT / "Sources/OpenJoystickDriver/App/Info.plist"
    if not app_info.is_file():
        die(f"Missing {app_info}")

    app_pattern = re.compile(
        r"(<key>CFBundleShortVersionString</key>\s*<string>)"
        r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?"
        r"(</string>)"
    )
    app_original = app_info.read_text()
    try:
        app_updated = replace_once(
            app_info,
            app_pattern,
            rf"\g<1>{version}\g<2>",
            "canonical app/package short version",
        )
    except MissingReference as error:
        print(f"missing expected version reference: {error}", file=sys.stderr)
        return 1

    if app_updated != app_original:
        app_info.write_text(app_updated)
        print(f"updated {app_info}")
    else:
        print("version references already up to date")
    print(f"Version set to {version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
