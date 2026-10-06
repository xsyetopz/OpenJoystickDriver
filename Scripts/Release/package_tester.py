"""Build a private, notarized Developer ID tester DMG."""

from __future__ import annotations

import datetime as dt
import os
import subprocess
import sys
from pathlib import Path

from .bundle_version import (
    current_commit_bundle_version,
    release_version,
    version_with_metadata,
)
from .package_common import (
    CommandFailure,
    cleanup_workdirs,
    default_bundle_short_version,
    die,
    embedded_dext,
    make_dmg,
    release_environment,
    require_clean_source,
    run,
    safe_version,
    verify_bundle_versions,
)

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parents[1]


def command_output(command: list[str]) -> str:
    result = subprocess.run(command, check=False, capture_output=True, text=True)
    if result.returncode:
        raise CommandFailure(result.returncode)
    return result.stdout.strip()


def usage() -> None:
    print("""Usage:
  ./Scripts/ojd package tester

Builds and packages the locally configured Developer ID app and its embedded
DriverKit extension into a notarized, shareable DMG without installing or
publishing it. The bundles carry the release SemVer and the commit's build
number; the DMG name and build-info file carry the SemVer with build metadata
(`+build.<number>.sha.<commit>`).""")


def tester_metadata(
    artifact_name: str,
    version: str,
    bundle_version: str,
) -> dict[str, str]:
    return {
        "artifact": artifact_name,
        "version": version,
        "bundle_version": bundle_version,
        "notarization": "accepted",
        "stapling": "validated",
        "gatekeeper": "accepted",
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

    short_version = release_version(default_bundle_short_version(PROJECT_DIR))
    build_dir = PROJECT_DIR / ".build"
    commit = require_clean_source(PROJECT_DIR, "Tester")
    build_version = current_commit_bundle_version(PROJECT_DIR)
    version = version_with_metadata(short_version, build_version, commit, dirty=False)
    try:
        short_commit = command_output(
            ["git", "-C", str(PROJECT_DIR), "rev-parse", "--short=12", "HEAD"]
        )
    except CommandFailure as error:
        return error.returncode
    tree_state = "clean"
    safe = safe_version(short_version)
    artifact_dir = build_dir / "tester-artifacts"
    artifact = (
        artifact_dir
        / f"OpenJoystickDriver-{safe}-tester-{build_version}-{short_commit}-macOS.dmg"
    )
    staging = build_dir / "tester-dmg-staging"
    rw_dmg = build_dir / f"OpenJoystickDriver-{safe}-tester-{build_version}-rw.dmg"
    mount_dir = build_dir / "tester-dmg-mount"
    app_path = build_dir / "debug/OpenJoystickDriver.app"
    notary_zip = build_dir / "OpenJoystickDriver-tester-notarize.zip"
    env = release_environment() | {
        "OJD_BUNDLE_SHORT_VERSION": short_version,
        "OJD_BUNDLE_VERSION": build_version,
        "OJD_SOURCE_COMMIT": commit,
        "OJD_SOURCE_STATE": tree_state,
    }
    artifact_dir.mkdir(parents=True, exist_ok=True)
    cleanup_workdirs((staging, mount_dir, rw_dmg, notary_zip, artifact), mount_dir)
    completed = False

    try:
        print("=== Build Developer ID app bundle ===")
        run(
            [
                "/usr/bin/env",
                "bash",
                str(SCRIPT_DIR / "../Build/build.sh"),
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
                str(SCRIPT_DIR / "../Build/build.sh"),
                "build",
                "dext",
            ],
            env=env,
        )
        if not app_path.is_dir():
            die(f"App bundle not found: {app_path}")
        dext_path = embedded_dext(app_path)
        verify_bundle_versions(
            app_path / "Contents/Info.plist",
            dext_path / "Info.plist",
            build_version,
            short_version,
            commit,
            tree_state,
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
        print("\n=== Notarize and staple tester app ===")
        notary_env = env | {
            "OJD_NOTARIZE_APP": str(app_path),
            "OJD_NOTARIZE_ZIP": str(notary_zip),
        }
        run(
            ["/usr/bin/env", "bash", str(SCRIPT_DIR / "notarize.sh"), "submit"],
            env=notary_env,
        )
        print("\n=== Verify notarization ticket and Gatekeeper acceptance ===")
        run(["/usr/bin/xcrun", "stapler", "validate", str(app_path)])
        run(
            [
                "/usr/sbin/spctl",
                "--assess",
                "--type",
                "execute",
                "--verbose=4",
                str(app_path),
            ]
        )
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
        metadata = tester_metadata(artifact.name, version, build_version)
        build_info.write_text(f"""OpenJoystickDriver local tester artifact

artifact: {metadata["artifact"]}
version: {metadata["version"]}
release_version: {short_version}
bundle_version: {metadata["bundle_version"]}
commit: {commit}
working_tree: {tree_state}
built_at_utc: {dt.datetime.now(dt.UTC).strftime("%Y-%m-%dT%H:%M:%SZ")}
app_signing_identity: {app_identity}
dext_signing_identity: {dext_identity}
notarization: {metadata["notarization"]}
stapling: {metadata["stapling"]}
gatekeeper: {metadata["gatekeeper"]}
recipient_source_checkout_required: no

This artifact contains the Developer ID-signed OpenJoystickDriver.app and its
embedded {dext_path.name}. It is notarized and stapled
for private testing with System Integrity Protection enabled.
Apple Development artifacts are not supported as arbitrary community tester
distribution and are not produced by this command.
""")
        print("\n=== Create tester DMG ===")
        make_dmg(staging, "OpenJoystickDriver Tester", artifact)
        cleanup_workdirs((staging, mount_dir, rw_dmg), mount_dir)
        run(["/usr/bin/hdiutil", "verify", str(artifact)])
        completed = True
    except CommandFailure as error:
        return error.returncode
    finally:
        cleanup = (staging, rw_dmg, mount_dir, notary_zip)
        if not completed:
            cleanup += (artifact,)
        cleanup_workdirs(cleanup, mount_dir)
    print(
        f"\nNotarized tester artifact ready (not installed or published):\n  {artifact}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
