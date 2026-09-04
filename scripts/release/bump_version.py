"""Update the repository's release version references."""

from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import NoReturn

VERSION = re.compile(
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-(?:alpha|beta|rc)\.[1-9][0-9]*)?$"
)
ROOT = Path(__file__).resolve().parents[2]


def die(message: str) -> NoReturn:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(2)


def usage() -> None:
    print("""Usage:
  ./scripts/ojd release bump-version <version>

Examples:
  ./scripts/ojd release bump-version 0.1.0-rc.2
  ./scripts/ojd release bump-version 0.1.0

Updates:
  - Sources/OpenJoystickDriver/App/Info.plist canonical app/package version
  - scripts/README.md release examples

    The target version must already have a Keep a Changelog heading:
    ## [<version>] - YYYY-MM-DD""")


class MissingReference(Exception):
    """A required version-owned reference was not found."""


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
    if version in {"", "-h", "--help", "help"}:
        usage()
        return 0
    if len(argv) != 1 or VERSION.fullmatch(version) is None:
        die("Version must be SemVer, for example 0.1.0-rc.2")

    app_info = ROOT / "Sources/OpenJoystickDriver/App/Info.plist"
    scripts_readme = ROOT / "scripts/README.md"
    changelog = ROOT / "CHANGELOG.md"
    for path in (app_info, scripts_readme, changelog):
        if not path.is_file():
            die(f"Missing {path}")
    changelog_heading = re.compile(
        rf"^## \[{re.escape(version)}\] - \d{{4}}-\d{{2}}-\d{{2}}(?: \[YANKED\])?$"
    )
    if not any(
        changelog_heading.fullmatch(line) for line in changelog.read_text().splitlines()
    ):
        die(f"CHANGELOG.md must contain heading: ## [{version}] - YYYY-MM-DD")

    app_pattern = re.compile(
        r"(<key>CFBundleShortVersionString</key>\s*<string>)"
        r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?"
        r"(</string>)"
    )
    readme_patterns = (
        (
            re.compile(
                r"\./scripts/ojd release package \d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?"
            ),
            f"./scripts/ojd release package {version}",
            "scripts README package release example",
        ),
        (
            re.compile(
                r"`\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?` and by manual dispatch"
            ),
            f"`{version}` and by manual dispatch",
            "scripts README manual dispatch version example",
        ),
    )

    app_original = app_info.read_text()
    readme_original = scripts_readme.read_text()
    try:
        app_updated = replace_once(
            app_info,
            app_pattern,
            rf"\g<1>{version}\g<2>",
            "canonical app/package short version",
        )
        readme_updated = readme_original
        for pattern, replacement, description in readme_patterns:
            readme_updated, count = pattern.subn(replacement, readme_updated, count=1)
            if count != 1:
                raise MissingReference(f"{scripts_readme}: {description}")
    except MissingReference as error:
        print(f"missing expected version reference: {error}", file=sys.stderr)
        return 1

    changed = False
    if app_updated != app_original:
        app_info.write_text(app_updated)
        print(f"updated {app_info}")
        changed = True
    if readme_updated != readme_original:
        scripts_readme.write_text(readme_updated)
        print(f"updated {scripts_readme}")
        changed = True
    if not changed:
        print("version references already up to date")
    print(f"Version set to {version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
