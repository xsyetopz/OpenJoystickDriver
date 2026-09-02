"""Package and atomically replace the local application installation."""

from __future__ import annotations

import os
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path
from typing import NoReturn

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parents[1]
sys.path.insert(0, str(SCRIPT_DIR))
from package_common import CommandFailure


def die(message: str) -> NoReturn:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(2)


def run(command: list[str]) -> None:
    result = subprocess.run(command, check=False)
    if result.returncode:
        code = 128 - result.returncode if result.returncode < 0 else result.returncode
        raise CommandFailure(code)


def main(argv: list[str]) -> int:
    if len(argv) > 1:
        die("release install-local accepts at most one argument")
    info = PROJECT_DIR / "Sources/OpenJoystickDriver/App/Info.plist"
    version = (
        argv[0]
        if argv
        else str(plistlib.loads(info.read_bytes())["CFBundleShortVersionString"])
    )
    app_source = PROJECT_DIR / ".build/debug/OpenJoystickDriver.app"
    destination = Path("/Applications/OpenJoystickDriver.app")
    staged = destination.parent / f".OpenJoystickDriver.app.staged.{os.getpid()}"
    backup = destination.parent / f".OpenJoystickDriver.app.backup.{os.getpid()}"

    try:
        run([sys.executable, str(SCRIPT_DIR / "package.py"), "release", version])
        if not app_source.is_dir():
            die(f"Release package did not produce {app_source}")
        run(["/usr/bin/ditto", str(app_source), str(staged)])
        run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(staged)])
        if destination.is_dir():
            staged_backup = backup
            destination.rename(staged_backup)
        else:
            staged_backup = None
        staged.rename(destination)
        run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(destination)])
        if staged_backup:
            shutil.rmtree(staged_backup)
    except CommandFailure as error:
        return error.returncode
    finally:
        if staged.exists():
            shutil.rmtree(staged)
        if backup.is_dir() and not destination.exists():
            backup.rename(destination)
        elif backup.exists():
            shutil.rmtree(backup)
    print(f"Installed OpenJoystickDriver {version} at {destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
