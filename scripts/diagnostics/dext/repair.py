"""Repair stale OpenJoystickDriver DriverKit process state."""

from __future__ import annotations

import os
import subprocess
import sys
import time
from pathlib import Path
from typing import NoReturn

DEXT_ID = "com.openjoystickdriver.XboxUSBDevice"
PROCESS_NAME = "XboxUSBDevice"


def die(message: str) -> NoReturn:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(2)


def processes() -> list[tuple[int, str]]:
    result = subprocess.run(
        ["ps", "-axo", "pid=,command="], capture_output=True, text=True, check=True
    )
    found = []
    for line in result.stdout.splitlines():
        fields = line.strip().split(maxsplit=1)
        if len(fields) == 2 and PROCESS_NAME in fields[1] and DEXT_ID in fields[1]:
            try:
                found.append((int(fields[0]), fields[1]))
            except ValueError:
                pass
    return found


def main() -> int:
    if os.uname().sysname != "Darwin":
        die("DriverKit repair is macOS-only")
    candidates = list(
        Path("/Library/SystemExtensions").glob(f"**/{DEXT_ID}.dext/{PROCESS_NAME}")
    )
    if not candidates:
        die(f"No installed {DEXT_ID} binary found in /Library/SystemExtensions")
    expected = max(candidates, key=lambda path: path.stat().st_mtime)
    print("Expected active dext binary:\n  " + str(expected) + "\n")
    stale = False
    for pid, command in processes():
        if command.startswith(str(expected)):
            print(
                f"Active dext process is already on expected path:\n  pid={pid} {command}"
            )
            continue
        stale = True
        print(f"Killing stale dext process:\n  pid={pid} {command}")
        subprocess.run(["sudo", "kill", "-9", str(pid)], check=True)
    if not stale:
        print("No stale dext process found.")
    print("\nWaiting for macOS to settle DriverKit process state...")
    time.sleep(2)
    extensions = subprocess.run(
        ["systemextensionsctl", "list"], capture_output=True, text=True, check=False
    )
    print("\nCurrent OpenJoystickDriver system extensions:")
    print(
        "\n".join(
            line
            for line in (extensions.stdout + extensions.stderr).splitlines()
            if DEXT_ID in line
        )
    )
    print("\nCurrent dext processes:")
    print("\n".join(f"{pid} {command}" for pid, command in processes()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
