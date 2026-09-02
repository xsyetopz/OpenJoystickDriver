"""Generate the shared app and DriverKit bundle build versions."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path
from typing import NoReturn

SEMANTIC_VERSION = re.compile(
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-(alpha|beta|rc)\.([1-9][0-9]*))?$"
)
DEXT_VERSION = re.compile(
    r"((?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]*)){0,2})"
    r"(?:(?:d|a|b|fc)([0-9]+))?"
)


def die(message: str) -> NoReturn:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(2)


def bundle_version_from_commit_count(commit_count: str) -> str:
    if not commit_count.isdecimal():
        die(f"Git commit count is not numeric: {commit_count}")
    count = int(commit_count)
    first, remainder = 1 + count // 10_000, count % 10_000
    second, third = remainder // 100, remainder % 100
    if not 1 <= first <= 9_999:
        die(
            f"Git commit count exceeds the supported CFBundleVersion range: {commit_count}"
        )
    return f"{first}.{second}.{third}"


def current_commit_bundle_version(project_dir: Path) -> str:
    result = subprocess.run(
        ["git", "-C", str(project_dir), "rev-list", "--count", "HEAD"],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode:
        die("Unable to count commits for CFBundleVersion")
    return bundle_version_from_commit_count(result.stdout.strip())


def tester_bundle_version(base_version: str, state_file: Path) -> str:
    previous_base, sequence = "", 0
    if state_file.is_file():
        values = {}
        for line in state_file.read_text().splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                values.setdefault(key, value)
        previous_base = values.get("base", "")
        try:
            sequence = int(values.get("sequence", "0"))
        except ValueError:
            sequence = 0
    sequence = sequence + 1 if previous_base == base_version else 1
    if not 1 <= sequence <= 255:
        die(
            f"Tester build sequence exceeded d255 for CFBundleVersion base {base_version}"
        )
    state_file.write_text(f"base={base_version}\nsequence={sequence}\n")
    return f"{base_version}d{sequence}"


def dext_bundle_version_from_semver(version: str) -> str:
    """Map the release SemVer grammar to Apple's kext version grammar."""
    match = SEMANTIC_VERSION.fullmatch(version)
    if match is None:
        die(
            "Version must be MAJOR.MINOR.PATCH, -alpha.N, -beta.N, or -rc.N "
            "with positive prerelease level"
        )
    major, minor, revision = (int(match.group(index)) for index in range(1, 4))
    if major > 65535 or minor > 99 or revision > 99:
        die("DriverKit version components exceed the kext version range")
    stage, level_text = match.group(4), match.group(5)
    if stage is None:
        return f"{major}.{minor}.{revision}"
    level = int(level_text)
    if level > 255:
        die("DriverKit prerelease level must be 1...255")
    stage_suffix = {"alpha": "a", "beta": "b", "rc": "fc"}[stage]
    return f"{major}.{minor}.{revision}{stage_suffix}{level}"


def validate_dext_bundle_version(version: str) -> str:
    match = DEXT_VERSION.fullmatch(version)
    if match is None:
        die("DriverKit CFBundleVersion has invalid grammar")
    components = [int(part) for part in match.group(1).split(".")]
    major, minor, revision = (components + [0, 0, 0])[:3]
    level = int(match.group(2)) if match.group(2) else None
    if (
        major > 65535
        or minor > 99
        or revision > 99
        or (level is not None and not 1 <= level <= 255)
    ):
        die("DriverKit CFBundleVersion components exceed supported bounds")
    return version


def resolve_dext_bundle_version(
    short_version: str, override: str | None = None, *, release: bool = False
) -> str:
    expected = dext_bundle_version_from_semver(short_version)
    if override is None:
        return expected
    explicit = validate_dext_bundle_version(override)
    if release and explicit != expected:
        die("Explicit DriverKit version conflicts with the release semantic version")
    return explicit


if __name__ == "__main__":
    match sys.argv[1:]:
        case ["--dext", version]:
            print(dext_bundle_version_from_semver(version))
        case ["--validate-dext", version]:
            print(validate_dext_bundle_version(version))
        case ["--resolve-dext", short_version]:
            print(resolve_dext_bundle_version(short_version))
        case ["--resolve-dext", short_version, override]:
            print(resolve_dext_bundle_version(short_version, override))
        case ["--resolve-dext", short_version, override, "--release"]:
            print(resolve_dext_bundle_version(short_version, override, release=True))
        case [project_dir]:
            print(current_commit_bundle_version(Path(project_dir)))
        case _:
            raise SystemExit(
                f"usage: {Path(sys.argv[0]).name} <project-dir> | --dext <version>"
            )
