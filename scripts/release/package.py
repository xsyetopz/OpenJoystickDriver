"""Build, notarize, and package the signed release application."""

from __future__ import annotations

import os
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

from bundle_version import (
    current_commit_bundle_version,
    dext_bundle_version_from_semver,
)
from package_common import (
    CommandFailure,
    cleanup_workdirs,
    default_bundle_short_version,
    detach_if_mounted,
    die,
    make_dmg,
    mounted,
    release_environment,
    run,
    safe_version,
    verify_bundle_versions,
)


def usage() -> None:
    print("""Usage:
  OJD_ENV=release ./scripts/ojd package release [version]

Builds a release-signed app, embeds the DriverKit extension, submits it for
notarization, staples the accepted ticket, and writes:

  .build/release-artifacts/OpenJoystickDriver-<version>-macOS.dmg

This does not install the app, register a login item, or submit a sysext
activation request on the build machine.""")


def main(argv: list[str]) -> int:
    if argv and argv[0] in {"-h", "--help", "help"}:
        usage()
        return 0
    if not argv or argv[0] != "release":
        die(
            f"Unknown package command: {argv[0] if argv else '<empty>'} (expected: release)"
        )
    if len(argv) > 2:
        die("package release accepts at most one version")
    if os.environ.get("OJD_ENV") != "release":
        die("package release requires OJD_ENV=release")

    release_ref = os.environ.get("GITHUB_REF_NAME", "")
    version = argv[1] if len(argv) == 2 else ""
    version = (
        version
        or release_ref.removeprefix("v")
        or default_bundle_short_version(PROJECT_DIR)
    )
    safe = safe_version(version)
    build_dir = PROJECT_DIR / ".build"
    artifact_dir = build_dir / "release-artifacts"
    app_path = build_dir / "debug/OpenJoystickDriver.app"
    notary_zip = build_dir / "OpenJoystickDriver-notarize.zip"
    artifact = artifact_dir / f"OpenJoystickDriver-{safe}-macOS.dmg"
    staging = build_dir / "dmg-staging"
    rw_dmg = build_dir / f"OpenJoystickDriver-{safe}-rw.dmg"
    mount_dir = build_dir / "dmg-mount"
    env = release_environment()
    env["OJD_BUNDLE_SHORT_VERSION"] = version
    env["OJD_BUNDLE_VERSION"] = current_commit_bundle_version(PROJECT_DIR)
    dext_version = dext_bundle_version_from_semver(version)
    artifact_dir.mkdir(parents=True, exist_ok=True)

    try:
        print("=== Build release app bundle ===")
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
        dext_env = env | {"OJD_SKIP_INSTALL": "1", "DEXT_BUNDLE_VERSION": dext_version}
        run(
            [
                "/usr/bin/env",
                "bash",
                str(SCRIPT_DIR / "../build-tools/build.sh"),
                "build",
                "dext",
            ],
            env=dext_env,
        )
        if not app_path.is_dir():
            die(f"App bundle not found: {app_path}")
        dext_info = (
            app_path
            / "Contents/Library/SystemExtensions/com.openjoystickdriver.XboxUSBDevice.dext/Info.plist"
        )
        verify_bundle_versions(
            app_path / "Contents/Info.plist",
            dext_info,
            env["OJD_BUNDLE_VERSION"],
            dext_version,
            version,
        )
        print("\n=== Verify signed app before notarization ===")
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
        print("\n=== Notarize and staple ===")
        notary_env = env | {
            "OJD_NOTARIZE_APP": str(app_path),
            "OJD_NOTARIZE_ZIP": str(notary_zip),
        }
        run(
            ["/usr/bin/env", "bash", str(SCRIPT_DIR / "notarize.sh"), "submit"],
            env=notary_env,
        )
        print("\n=== Verify notarized app ===")
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
        print("\n=== Create drag-and-drop DMG ===")
        detach_if_mounted(mount_dir)
        if mounted(mount_dir):
            die(f"Mount path is still active; refusing to remove: {mount_dir}")
        cleanup_workdirs((staging, rw_dmg, mount_dir, artifact), mount_dir)
        staging.mkdir(parents=True)
        run(["/usr/bin/ditto", str(app_path), str(staging / "OpenJoystickDriver.app")])
        (staging / "Applications").symlink_to("/Applications")
        make_dmg(staging, "OpenJoystickDriver", artifact)
        cleanup_workdirs((staging, rw_dmg, mount_dir), mount_dir)
        identity = os.environ.get("CODESIGN_IDENTITY", "-")
        if identity not in {"", "-"}:
            run(["/usr/bin/codesign", "--sign", identity, "--timestamp", str(artifact)])
            run(["/usr/bin/codesign", "--verify", "--verbose=2", str(artifact)])
        else:
            print(
                "WARNING: CODESIGN_IDENTITY not set; skipping DMG codesign.",
                file=sys.stderr,
            )
        run(["/usr/bin/hdiutil", "verify", str(artifact)])
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
    except CommandFailure as error:
        return error.returncode
    finally:
        cleanup_workdirs((staging, rw_dmg, mount_dir), mount_dir)
    print(f"\nRelease artifact ready:\n  {artifact}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
