#!/usr/bin/env python3
"""Validate OJD env structure without reading secret values into output."""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
PROFILES = {
    "dev": {
        "CODESIGN_IDENTITY", "DEVELOPMENT_TEAM", "DEXT_BUILD_PROFILE",
        "APPLE_DEV_IDENTITY", "GUI_PROVISIONING_PROFILE",
    },
    "release": {
        "CODESIGN_IDENTITY", "GUI_CODESIGN_IDENTITY",
        "DEVELOPMENT_TEAM",
        "DEXT_BUILD_IDENTITY", "DEXT_BUILD_PROFILE",
        "GUI_PROVISIONING_PROFILE",
        "DEVID_APP_IDENTITY", "NOTARIZE_APPLE_ID",
        "NOTARIZE_PASSWORD", "NOTARIZE_KEYCHAIN_PROFILE",
        "SPARKLE_PUBLIC_ED_KEY", "SPARKLE_ED_PRIVATE_KEY",
        "SPARKLE_FEED_URL",
    },
}
LEGACY = [ROOT / ".env", ROOT / "scripts/.env", ROOT / "scripts/.env.dev", ROOT / "scripts/.env.release"]
ASSIGNMENT = re.compile(r"^(?:export )?([A-Z][A-Z0-9_]*)=")


def keys(path: pathlib.Path) -> tuple[set[str], list[int]]:
    found: set[str] = set()
    malformed: list[int] = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        match = ASSIGNMENT.match(stripped)
        if match:
            found.add(match.group(1))
        else:
            malformed.append(number)
    return found, malformed


def main() -> int:
    failed = False
    for path in LEGACY:
        if path.exists():
            print(f"[FAIL] legacy env file is no longer loaded: {path.relative_to(ROOT)}")
            failed = True
    for profile, allowed in PROFILES.items():
        path = ROOT / f".env.{profile}"
        if not path.exists():
            print(f"[INFO] {path.name} absent; use {path.name}.example or signing configure")
            continue
        found, malformed = keys(path)
        unknown = sorted(found - allowed)
        if malformed:
            print(f"[FAIL] {path.name} has malformed non-comment lines: {malformed}")
            failed = True
        if unknown:
            print(f"[FAIL] {path.name} has unsupported keys: {", ".join(unknown)}")
            failed = True
        if not malformed and not unknown:
            print(f"[OK] {path.name}: {len(found)} recognized key(s); values suppressed")
    print("[OK] GitHub Actions secret key names remain owned by .github/workflows/release.yml")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
