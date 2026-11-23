from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import NoReturn

from .bundle_version import RELEASE_TAG, release_version

ROOT = Path(__file__).resolve().parents[2]
# Agent plugin manifests carry the app version, so an installed plugin names the release it documents.
PLUGIN_MANIFESTS = (
    Path("plugins/claude/openjoystickdriver/.claude-plugin/plugin.json"),
    Path("plugins/codex/openjoystickdriver/plugin.json"),
)
PLUGIN_VERSION = re.compile(r'("version": ")([^"]+)(")')


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


PRERELEASES = ("alpha", "beta", "rc")
PARTS = ("major", "minor", "patch", "release", "prerelease", *PRERELEASES)
VERSION_PARTS = re.compile(r"(\d+)\.(\d+)\.(\d+)(?:-(alpha|beta|rc)\.(\d+))?")


def next_version(current: str, part: str) -> str:
    match = VERSION_PARTS.fullmatch(current) if RELEASE_TAG.fullmatch(current) else None
    if match is None:
        die(f"Current version is not MAJOR.MINOR.PATCH[-alpha|beta|rc.N]: {current}")
    major, minor, patch = (int(group) for group in match.groups()[:3])
    label, number = match.group(4), int(match.group(5) or 0)
    if part == "major":
        return f"{major + 1}.0.0"
    if part == "minor":
        return f"{major}.{minor + 1}.0"
    if part == "patch":
        return f"{major}.{minor}.{patch + 1}"
    if label is None:
        if part in ("release", "prerelease"):
            die(f"{current} is a release, so it has no prerelease to {part}")
        return f"{major}.{minor}.{patch + 1}-{part}.1"
    if part == "release":
        return f"{major}.{minor}.{patch}"
    if part == "prerelease":
        return f"{major}.{minor}.{patch}-{label}.{number + 1}"
    if PRERELEASES.index(part) <= PRERELEASES.index(label):
        die(f"{current} cannot go back to {part}")
    return f"{major}.{minor}.{patch}-{part}.1"


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        die(
            "usage: just release-bump-version <version|"
            + "|".join(PARTS)
            + ">, for example 0.1.0-rc.2 or prerelease"
        )

    app_info = ROOT / "Sources/OpenJoystickDriver/App/Info.plist"
    if not app_info.is_file():
        die(f"Missing {app_info}")

    app_pattern = re.compile(
        r"(<key>CFBundleShortVersionString</key>\s*<string>)"
        r"(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?)"
        r"(</string>)"
    )
    app_original = app_info.read_text()
    current = app_pattern.search(app_original)
    version = (
        next_version(current.group(2), argv[0])
        if current is not None and argv[0] in PARTS
        else argv[0]
    )
    release_version(version)
    targets = [(app_info, app_pattern, "canonical app/package short version")]
    for manifest in PLUGIN_MANIFESTS:
        if not (ROOT / manifest).is_file():
            die(f"Missing {ROOT / manifest}")
        targets.append((ROOT / manifest, PLUGIN_VERSION, "agent plugin version"))
    try:
        updates = [
            (
                path,
                path.read_text(),
                replace_once(path, pattern, rf"\g<1>{version}\g<3>", what),
            )
            for path, pattern, what in targets
        ]
    except MissingReference as error:
        print(f"missing expected version reference: {error}", file=sys.stderr)
        return 1

    changed = [(path, text) for path, original, text in updates if text != original]
    for path, text in changed:
        path.write_text(text)
        print(f"updated {path}")
    if not changed:
        print("version references already up to date")
    print(f"Version set to {version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
