"""Build a private, unnotarized Developer ID tester DMG."""

from __future__ import annotations

import datetime as dt
import os
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parents[1]
sys.path.insert(0, str(SCRIPT_DIR))
from bundle_version import (
    current_commit_bundle_version,
    dext_bundle_version_from_semver,
    tester_bundle_version,
)
from package_common import (
    CommandFailure,
    cleanup_workdirs,
    default_bundle_short_version,
    die,
    make_dmg,
    release_environment,
    run,
    safe_version,
    verify_bundle_versions,
)


def command_output(command: list[str]) -> str:
    result = subprocess.run(command, check=False, capture_output=True, text=True)
    if result.returncode:
        raise CommandFailure(result.returncode)
    return result.stdout.strip()


def usage() -> None:
    print("""Usage:
  ./scripts/ojd package tester

Builds and packages the locally configured Developer ID app and its embedded
DriverKit extension into a shareable DMG without installing, publishing, or
notarizing it. The DMG includes source and bundle-build metadata.""")


def tester_metadata(
    artifact_name: str,
    version: str,
    app_build_version: str,
    dext_bundle_version: str,
) -> dict[str, str]:
    return {
        "artifact": artifact_name,
        "version": version,
        "app_bundle_build_version": app_build_version,
        "dext_bundle_version": dext_bundle_version,
    }


def main(argv: list[str]) -> int:
    if (
        not argv
        or argv[0] in {"-h", "--help", "help"}
        or any(argument in {"-h", "--help", "help"} for argument in argv[1:])
    ):
        usage()
        return 0
    if argv[0] != "tester":
        die(f"Unknown package command: {argv[0]} (expected: tester)")
    if len(argv) != 1:
        die("package tester does not accept arguments")
    if os.environ.get("OJD_ENV") != "release":
        die("package tester requires OJD_ENV=release")

    version = default_bundle_short_version(PROJECT_DIR)
    build_dir = PROJECT_DIR / ".build"
    state_file = build_dir / "tester-build-version"
    base = current_commit_bundle_version(PROJECT_DIR)
    build_version = tester_bundle_version(base, state_file)
    dext_version = dext_bundle_version_from_semver(version)
    try:
        commit = command_output(
            ["git", "-C", str(PROJECT_DIR), "rev-parse", "--verify", "HEAD"]
        )
        short_commit = command_output(
            ["git", "-C", str(PROJECT_DIR), "rev-parse", "--short=12", "HEAD"]
        )
        dirty = bool(
            command_output(
                [
                    "git",
                    "-C",
                    str(PROJECT_DIR),
                    "status",
                    "--porcelain",
                    "--untracked-files=all",
                ]
            )
        )
    except CommandFailure as error:
        return error.returncode
    tree_state = "dirty" if dirty else "clean"
    safe = safe_version(version)
    artifact_dir = build_dir / "tester-artifacts"
    artifact = (
        artifact_dir
        / f"OpenJoystickDriver-{safe}-tester-{build_version}-{short_commit}{'-dirty' if dirty else ''}-macOS.dmg"
    )
    staging = build_dir / "tester-dmg-staging"
    rw_dmg = build_dir / f"OpenJoystickDriver-{safe}-tester-{build_version}-rw.dmg"
    mount_dir = build_dir / "tester-dmg-mount"
    app_path = build_dir / "debug/OpenJoystickDriver.app"
    dext_path = (
        app_path
        / "Contents/Library/SystemExtensions/com.openjoystickdriver.XboxUSBDevice.dext"
    )
    env = release_environment() | {
        "OJD_BUNDLE_SHORT_VERSION": version,
        "OJD_BUNDLE_VERSION": build_version,
        "DEXT_BUNDLE_VERSION": dext_version,
    }
    artifact_dir.mkdir(parents=True, exist_ok=True)

    try:
        print("=== Build Developer ID app bundle ===")
        run(
            [
                "/usr/bin/env",
                "bash",
                str(SCRIPT_DIR / "../build-tools/build.sh"),
                "build",
                "release",
            ],
            env=env,
        )
        print("\n=== Build and embed DriverKit extension ===")
        run(
            [
                "/usr/bin/env",
                "bash",
                str(SCRIPT_DIR / "../build-tools/build.sh"),
                "build",
                "dext",
            ],
            env=env | {"OJD_SKIP_INSTALL": "1"},
        )
        if not app_path.is_dir():
            die(f"App bundle not found: {app_path}")
        if not dext_path.is_dir():
            die(f"Embedded DriverKit extension not found: {dext_path}")
        verify_bundle_versions(
            app_path / "Contents/Info.plist",
            dext_path / "Info.plist",
            build_version,
            dext_version,
            version,
        )
        print("\n=== Verify Developer ID signatures ===")
        run(
            [
                "/usr/bin/codesign",
                "--verify",
                "--deep",
                "--strict",
                "--verbose=2",
                str(app_path),
            ]
        )
        run(
            [
                "/usr/bin/codesign",
                "--verify",
                "--deep",
                "--strict",
                "--verbose=2",
                str(dext_path),
            ]
        )
        cleanup_workdirs((staging, mount_dir, rw_dmg, artifact), mount_dir)
        staging.mkdir(parents=True)
        run(["/usr/bin/ditto", str(app_path), str(staging / "OpenJoystickDriver.app")])
        (staging / "Applications").symlink_to("/Applications")
        build_info = staging / "OpenJoystickDriver-TESTER-BUILD.txt"
        app_identity = os.environ.get(
            "GUI_CODESIGN_IDENTITY", os.environ.get("CODESIGN_IDENTITY", "-")
        )
        dext_identity = os.environ.get(
            "DEXT_BUILD_IDENTITY", os.environ.get("CODESIGN_IDENTITY", "-")
        )
        build_info.write_text(f"""OpenJoystickDriver local tester artifact

artifact: {artifact.name}
version: {version}
app_bundle_build_version: {build_version}
dext_bundle_version: {dext_version}
commit: {commit}
working_tree: {tree_state}
built_at_utc: {dt.datetime.now(dt.UTC).strftime("%Y-%m-%dT%H:%M:%SZ")}
app_signing_identity: {app_identity}
dext_signing_identity: {dext_identity}
notarization: not notarized (private local tester build)
recipient_source_checkout_required: no

This artifact contains the Developer ID-signed OpenJoystickDriver.app and its
embedded com.openjoystickdriver.XboxUSBDevice.dext. It is for private testing;
it is not notarized and the recipient may need an explicit Gatekeeper override.
Apple Development artifacts are not supported as arbitrary community tester
distribution and are not produced by this command.
""")
        print("\n=== Create tester DMG ===")
        make_dmg(staging, "OpenJoystickDriver Tester", artifact)
        cleanup_workdirs((staging, mount_dir, rw_dmg), mount_dir)
        run(["/usr/bin/hdiutil", "verify", str(artifact)])
    except CommandFailure as error:
        return error.returncode
    finally:
        cleanup_workdirs((staging, rw_dmg, mount_dir), mount_dir)
    print(f"\nLocal tester artifact ready (not installed or published):\n  {artifact}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
