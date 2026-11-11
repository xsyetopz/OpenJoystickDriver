from __future__ import annotations

import plistlib
import subprocess
import sys
from pathlib import Path
from typing import NoReturn

from .package_common import CommandFailure

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parents[1]


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

    try:
        run([sys.executable, "-m", "Scripts.Release.package", "release", version])
        if not app_source.is_dir():
            die(f"Release package did not produce {app_source}")
        run(
            [
                sys.executable,
                "-m",
                "Scripts.Build.install_app",
                "--retire-driverkit",
                str(app_source),
            ]
        )
    except CommandFailure as error:
        return error.returncode
    print(
        f"Installed OpenJoystickDriver {version} at /Applications/OpenJoystickDriver.app"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
