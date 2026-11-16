from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path
from typing import NoReturn

SEMVER = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)"
    r"(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?"
    r"(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$"
)
BUNDLE_VERSION = re.compile(
    r"((?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]*)){0,2})(?:(d|a|b|fc)([0-9]+))?"
)
RELEASE_TAG = re.compile(
    r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-(?:alpha|beta|rc)\.[1-9][0-9]*)?"
)
TESTER_AFTER_PRERELEASE = re.compile(
    r"((?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)-(?:alpha|beta|rc)\.[1-9][0-9]*)"
    r"\.tester\.[1-9][0-9]*"
)
TESTER_AFTER_RELEASE = re.compile(
    r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.([1-9][0-9]*)-tester\.[1-9][0-9]*"
)


def die(message: str) -> NoReturn:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(2)


def release_version(version: str) -> str:
    match = SEMVER.fullmatch(version)
    if match is None:
        die(f"Release version is not SemVer 2.0.0: {version}")
    if match.group(5) is not None:
        die(f"Release version must not carry build metadata: {version}")
    return version


def release_tag_kind(tag: str) -> str:
    if RELEASE_TAG.fullmatch(tag) is not None:
        return "prerelease" if "-" in tag else "release"
    if TESTER_AFTER_PRERELEASE.fullmatch(tag) or TESTER_AFTER_RELEASE.fullmatch(tag):
        return "tester"
    die(
        "release tag must be MAJOR.MINOR.PATCH with optional -alpha.N, -beta.N, or -rc.N, "
        f"or a tester tag (PRERELEASE.tester.N, or MAJOR.MINOR.PATCH-tester.N with PATCH >= 1): {tag}"
    )


def tester_base_tag(tag: str) -> str:
    if release_tag_kind(tag) != "tester":
        die(f"Not a tester tag: {tag}")
    if (match := TESTER_AFTER_PRERELEASE.fullmatch(tag)) is not None:
        return match.group(1)
    match = TESTER_AFTER_RELEASE.fullmatch(tag)
    assert match is not None
    return f"{match.group(1)}.{match.group(2)}.{int(match.group(3)) - 1}"


def build_metadata(bundle_version: str, commit: str, dirty: bool) -> str:
    identifiers = ["build", bundle_version, "sha", commit[:12]]
    if dirty:
        identifiers.append("dirty")
    return ".".join(identifiers)


def version_with_metadata(
    version: str, bundle_version: str, commit: str, dirty: bool
) -> str:
    full = f"{release_version(version)}+{build_metadata(bundle_version, commit, dirty)}"
    if SEMVER.fullmatch(full) is None:
        die(f"Build metadata is not valid SemVer: {full}")
    return full


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


def validate_bundle_version(version: str) -> str:
    match = BUNDLE_VERSION.fullmatch(version)
    if match is None:
        die(f"CFBundleVersion has invalid grammar: {version}")
    components = [int(part) for part in match.group(1).split(".")]
    major, minor, revision = (components + [0, 0, 0])[:3]
    level = int(match.group(3)) if match.group(3) else None
    if (
        major > 65535
        or minor > 99
        or revision > 99
        or (level is not None and not 1 <= level <= 255)
    ):
        die(f"CFBundleVersion components exceed supported bounds: {version}")
    return version


def next_development_bundle_version(base: str, installed: list[str]) -> str:
    base_match = BUNDLE_VERSION.fullmatch(validate_bundle_version(base))
    if base_match is None or base_match.group(2):
        die(f"Base CFBundleVersion already has a stage: {base}")
    level = 0
    for candidate in installed:
        match = BUNDLE_VERSION.fullmatch(candidate)
        if match and match.group(1) == base and match.group(2) == "d":
            level = max(level, int(match.group(3)))
    return validate_bundle_version(f"{base}d{level + 1}")


def usage() -> NoReturn:
    raise SystemExit(
        f"usage: {Path(sys.argv[0]).name} <project-dir>\n"
        "       | --check-release <version>\n"
        "       | --tag-kind <tag> | --tester-base <tag>\n"
        "       | --validate <bundle-version>\n"
        "       | --next-dev <base-bundle-version> [installed-bundle-version...]"
    )


if __name__ == "__main__":
    match sys.argv[1:]:
        case ["--check-release", version]:
            print(release_version(version))
        case ["--tag-kind", tag]:
            print(release_tag_kind(tag))
        case ["--tester-base", tag]:
            print(tester_base_tag(tag))
        case ["--validate", version]:
            print(validate_bundle_version(version))
        case ["--next-dev", base, *installed]:
            print(next_development_bundle_version(base, installed))
        case [project_dir] if not project_dir.startswith("-"):
            print(current_commit_bundle_version(Path(project_dir)))
        case _:
            usage()
