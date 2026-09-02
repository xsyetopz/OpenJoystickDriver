"""Shared standard-library helpers for release DMG packaging."""

from __future__ import annotations

import os
import plistlib
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import NoReturn


def die(message: str) -> NoReturn:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(2)


class CommandFailure(Exception):
    """A child command failed; preserve its shell-visible exit status."""

    def __init__(self, returncode: int) -> None:
        self.returncode = 128 - returncode if returncode < 0 else returncode
        super().__init__(f"command exited with status {self.returncode}")


def run(command: list[str], *, env: dict[str, str] | None = None) -> None:
    result = subprocess.run(command, check=False, env=env)
    if result.returncode:
        raise CommandFailure(result.returncode)


def safe_version(version: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]", "-", version)


def default_bundle_short_version(project_dir: Path) -> str:
    info = project_dir / "Sources/OpenJoystickDriver/App/Info.plist"
    try:
        value = plistlib.loads(info.read_bytes())["CFBundleShortVersionString"]
    except (KeyError, OSError, plistlib.InvalidFileException) as error:
        die(f"Invalid or missing CFBundleShortVersionString in {info}: {error}")
    return str(value)


def mounted(path: Path) -> bool:
    result = subprocess.run(
        ["/sbin/mount"], check=False, capture_output=True, text=True
    )
    return any(f" on {path} " in line for line in result.stdout.splitlines())


def detach_if_mounted(path: Path) -> None:
    if path.is_dir() and mounted(path):
        run(["/usr/bin/hdiutil", "detach", str(path), "-quiet"])


def cleanup_workdirs(paths: tuple[Path, ...], mount_dir: Path) -> None:
    detach_if_mounted(mount_dir)
    if mounted(mount_dir):
        print(
            f"WARNING: Refusing to remove active DMG mount path: {mount_dir}",
            file=sys.stderr,
        )
        return
    for path in paths:
        if path.is_dir() and not path.is_symlink():
            shutil.rmtree(path)
        else:
            path.unlink(missing_ok=True)


def verify_bundle_versions(
    app_info: Path,
    dext_info: Path,
    app_build_version: str,
    dext_build_version: str,
    short_version: str,
) -> None:
    for label, path, expected in (
        ("App", app_info, app_build_version),
        ("DEXT", dext_info, dext_build_version),
    ):
        value: object | None = None
        try:
            info = plistlib.loads(path.read_bytes())
            value = info["CFBundleVersion"]
        except (KeyError, OSError, plistlib.InvalidFileException) as error:
            die(f"Unable to read {label} CFBundleVersion: {error}")
        if value != expected:
            die(f"{label} CFBundleVersion mismatch: expected {expected}, got {value}")
        if info.get("CFBundleShortVersionString") != short_version:
            die(f"{label} short version mismatch: expected {short_version}")


def make_dmg(staging_dir: Path, volume_name: str, artifact: Path) -> None:
    run(
        [
            "/usr/bin/hdiutil",
            "create",
            "-srcfolder",
            str(staging_dir),
            "-volname",
            volume_name,
            "-fs",
            "HFS+",
            "-format",
            "UDZO",
            str(artifact),
        ]
    )


def release_environment() -> dict[str, str]:
    environment = os.environ.copy()
    environment["OJD_ENV"] = "release"
    return environment
