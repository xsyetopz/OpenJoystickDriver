"""Smoke-test the foreground application bundle on macOS 10.15."""

from __future__ import annotations

import plistlib
import subprocess
import sys
from pathlib import Path


def fail(failures: list[str], message: str) -> None:
    failures.append(message)
    print(f"[FAIL] {message}", file=sys.stderr)


def check_file(path: Path, failures: list[str]) -> None:
    if path.is_file():
        print(f"[OK] found {path}")
    else:
        fail(failures, f"missing {path}")


def command_output(command: list[str]) -> str:
    try:
        result = subprocess.run(command, check=False, capture_output=True, text=True)
    except OSError:
        return ""
    return result.stdout.strip() if result.returncode == 0 else ""


def minimum_macos(binary: Path) -> str:
    lines = command_output(["/usr/bin/otool", "-l", str(binary)]).splitlines()
    mode = ""
    for line in lines:
        fields = line.split()
        if fields[:2] == ["cmd", "LC_BUILD_VERSION"]:
            mode = "build"
        elif fields[:2] == ["cmd", "LC_VERSION_MIN_MACOSX"]:
            mode = "min"
        elif mode and fields and fields[0] in {"minos", "version"}:
            return fields[1]
    return ""


def main(argv: list[str]) -> int:
    app = Path(argv[0]) if argv else Path("/Applications/OpenJoystickDriver.app")
    if len(argv) > 1:
        print("Usage: ./scripts/ojd diagnose catalina [app]", file=sys.stderr)
        return 2
    print("OpenJoystickDriver Catalina foreground smoke test")
    print(f"app: {app}")
    failures: list[str] = []
    if not app.is_dir():
        print(f"[FAIL] app bundle not found: {app}", file=sys.stderr)
        return 1
    info = app / "Contents/Info.plist"
    binary = app / "Contents/MacOS/OpenJoystickDriver"
    icon = app / "Contents/Resources/OpenJoystickDriver.icns"
    for path in (info, binary, icon):
        check_file(path, failures)
    try:
        minimum = plistlib.loads(info.read_bytes()).get("LSMinimumSystemVersion", "")
    except (OSError, plistlib.InvalidFileException):
        minimum = ""
    binary_minimum = minimum_macos(binary)
    architectures = command_output(["/usr/bin/lipo", "-archs", str(binary)])
    print(f"[INFO] LSMinimumSystemVersion: {minimum or 'missing'}")
    print(f"[INFO] binary minimum: {binary_minimum or 'missing'}")
    print(f"[INFO] architectures: {architectures or 'missing'}")
    if minimum != "10.15":
        fail(failures, "LSMinimumSystemVersion is not 10.15")
    if binary_minimum != "10.15":
        fail(failures, "binary does not target macOS 10.15")
    if "x86_64" not in architectures.split():
        fail(failures, "application is missing x86_64")
    obsolete = [
        path
        for path in (app / "Contents").rglob("*")
        if "LaunchAgents" in path.parts
        or path.name.startswith("OpenJoystickDriverDaemon")
    ]
    if obsolete:
        fail(failures, "bundle contains an obsolete agent or helper")
    else:
        print("[OK] bundle contains only the main runtime identity")
    try:
        headless_status = subprocess.run(
            [str(binary), "--headless", "--help"], check=False
        ).returncode
    except OSError:
        headless_status = 1
    if headless_status:
        fail(failures, "headless CLI failed to start")
    if failures:
        print(f"[FAIL] {len(failures)} check(s) failed", file=sys.stderr)
        return len(failures) + 1
    print("[OK] Catalina foreground checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
