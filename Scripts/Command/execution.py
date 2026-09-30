"""Command execution helpers."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import NoReturn

SCRIPT_DIR = Path(__file__).resolve().parents[1]
PROJECT_DIR = SCRIPT_DIR.parent
ENVIRONMENT = SCRIPT_DIR / "Platform/environment.sh"


def die(message: str) -> NoReturn:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(2)


def env_with(overrides: dict[str, str] | None = None) -> dict[str, str]:
    env = os.environ.copy()
    env.update(overrides or {})
    return env


def run_record(args: list[str]) -> int:
    if not args:
        die("diagnose record requires a canonical controller JSON path")
    record = Path(args[0]).expanduser()
    if not record.is_absolute():
        record = Path.cwd() / record
    command = [
        "/bin/bash",
        "-c",
        'source "$1"; cd "$2"; exec "$SWIFT_BIN" run OpenJoystickDriverHIDTool --record-probe "$3" "${@:4}"',
        "ojd",
        str(ENVIRONMENT),
        str(PROJECT_DIR),
        str(record),
        *args[1:],
    ]
    return subprocess.run(command, env=env_with(), check=False).returncode


def run_usb_passive(args: list[str]) -> int:
    if len(args) != 2:
        die("diagnose usb-passive requires vid pid (hex, for example 0x3537 0x1010)")
    command = [
        "/bin/bash",
        "-c",
        'source "$1"; cd "$2"; exec "$SWIFT_BIN" run OpenJoystickDriverHIDTool --usb-passive --vid "$3" --pid "$4"',
        "ojd",
        str(ENVIRONMENT),
        str(PROJECT_DIR),
        *args,
    ]
    overrides = {"OJD_ENABLE_CONTRIBUTOR_USB_PASSIVE": "1"}
    return subprocess.run(command, env=env_with(overrides), check=False).returncode


def run_commands(commands: list[list[str]]) -> int:
    for command in commands:
        result = subprocess.run(command, cwd=PROJECT_DIR, env=env_with(), check=False)
        if result.returncode:
            return result.returncode
    return 0


def repair_swiftpm_cache() -> int:
    if not (PROJECT_DIR / ".build").is_dir():
        return 0
    swift_package = os.environ.get("SWIFT_PACKAGE_BIN") or shutil.which("swift-package")
    if not swift_package:
        result = subprocess.run(
            ["xcrun", "--find", "swift-package"],
            capture_output=True,
            text=True,
            check=False,
        )
        swift_package = result.stdout.strip() if result.returncode == 0 else ""
    if not swift_package:
        die("swift-package not found")
    return subprocess.run(
        [swift_package, "clean"], cwd=PROJECT_DIR, check=False
    ).returncode
