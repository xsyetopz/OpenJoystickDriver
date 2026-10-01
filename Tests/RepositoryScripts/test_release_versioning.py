"""Behavior tests for release version and package metadata helpers."""

from __future__ import annotations

import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from Scripts.Release import package_tester
from Scripts.Release.bundle_version import (
    build_metadata,
    bundle_version_from_commit_count,
    next_development_bundle_version,
    release_version,
    validate_bundle_version,
    version_with_metadata,
)
from Scripts.Release.package_common import (
    require_clean_source,
    source_identity,
    verify_bundle_versions,
)

PROJECT_DIR = Path(__file__).resolve().parents[2]


def expect_failure(callable_, *args, **kwargs) -> None:
    try:
        callable_(*args, **kwargs)
    except SystemExit:
        return
    raise AssertionError(f"expected failure from {callable_.__name__}")


def executable_version(*args: str) -> str:
    result = subprocess.run(
        [sys.executable, "-m", "Scripts.Release.bundle_version", *args],
        cwd=PROJECT_DIR,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode:
        raise AssertionError(result.stderr)
    return result.stdout.strip()


def expect_executable_failure(*args: str) -> None:
    result = subprocess.run(
        [sys.executable, "-m", "Scripts.Release.bundle_version", *args],
        cwd=PROJECT_DIR,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode == 0:
        raise AssertionError(f"expected executable failure for {args}")


def validate_tester_packaging_flow(*, fail_after_dmg: bool) -> None:
    dext_names = ["com.openjoystickdriver.VirtualHIDDevice.dext"]
    with tempfile.TemporaryDirectory() as directory:
        project = Path(directory)
        events: list[str] = []
        verified_dexts: list[str] = []
        captured_build_info = ""
        captured_env: dict[str, str] = {}
        original_environment = os.environ.copy()
        overrides = {
            "PROJECT_DIR": project,
            "default_bundle_short_version": lambda _: "0.5.0-beta.4",
            "require_clean_source": lambda *_: "a" * 40,
            "current_commit_bundle_version": lambda _: "1.0.42",
            "command_output": lambda _: "aaaaaaaaaaaa",
            "release_environment": lambda: os.environ.copy(),
            "verify_bundle_versions": lambda _, dext, *__: verified_dexts.append(
                dext.parent.name
            ),
        }
        originals = {name: getattr(package_tester, name) for name in overrides}
        originals["run"] = package_tester.run
        originals["make_dmg"] = package_tester.make_dmg

        def fake_run(command: list[str], *, env: dict[str, str] | None = None) -> None:
            if command[-2:] == ["build", "release"]:
                assert env is not None
                captured_env.update(env)
                for name in dext_names:
                    dext = (
                        project
                        / ".build/debug/OpenJoystickDriver.app/Contents/Library/SystemExtensions"
                        / name
                    )
                    dext.mkdir(parents=True)
            elif command[0] == "/usr/bin/ditto":
                shutil.copytree(command[1], command[2])
            elif "notarize.sh" in " ".join(command):
                events.append("notarize")
                assert env is not None
                Path(env["OJD_NOTARIZE_ZIP"]).write_text("temporary upload")
            elif command[:3] == ["/usr/bin/xcrun", "stapler", "validate"]:
                events.append("stapler")
            elif command[0] == "/usr/sbin/spctl":
                events.append("gatekeeper")
            elif command[:2] == ["/usr/bin/hdiutil", "verify"] and fail_after_dmg:
                raise package_tester.CommandFailure(19)

        def fake_make_dmg(staging: Path, _: str, artifact: Path) -> None:
            nonlocal captured_build_info
            events.append("dmg")
            captured_build_info = (
                staging / "OpenJoystickDriver-TESTER-BUILD.txt"
            ).read_text()
            artifact.write_text("dmg")

        try:
            for name, value in overrides.items():
                setattr(package_tester, name, value)
            package_tester.run = fake_run
            package_tester.make_dmg = fake_make_dmg
            os.environ.clear()
            os.environ["OJD_ENV"] = "release"
            result = package_tester.main(["tester"])
        finally:
            os.environ.clear()
            os.environ.update(original_environment)
            for name, value in originals.items():
                setattr(package_tester, name, value)

        artifacts = list((project / ".build/tester-artifacts").glob("*.dmg"))
        if fail_after_dmg:
            assert result == 19
            assert artifacts == []
        else:
            assert result == 0
            assert len(artifacts) == 1
            assert verified_dexts == sorted(dext_names)
            assert f"embedded {', '.join(sorted(dext_names))}." in captured_build_info
            assert events == ["notarize", "stapler", "gatekeeper", "dmg"]
            assert artifacts[0].name == (
                "OpenJoystickDriver-0.5.0-beta.4-tester-1.0.42-aaaaaaaaaaaa-macOS.dmg"
            )
            assert captured_env["OJD_BUNDLE_SHORT_VERSION"] == "0.5.0-beta.4"
            assert captured_env["OJD_BUNDLE_VERSION"] == "1.0.42"
            assert "DEXT_BUNDLE_VERSION" not in captured_env
            assert (
                "version: 0.5.0-beta.4+build.1.0.42.sha.aaaaaaaaaaaa\n"
                in captured_build_info
            )
            for line in (
                "notarization: accepted",
                "stapling: validated",
                "gatekeeper: accepted",
            ):
                assert line in captured_build_info
        for path in (
            project / ".build/tester-dmg-staging",
            project / ".build/tester-dmg-mount",
            project / ".build/OpenJoystickDriver-tester-notarize.zip",
        ):
            assert not path.exists()


def main() -> int:
    for value in ("0.5.0", "0.5.0-beta.5", "1.0.0-rc.1.2", "1.0.0-x-y.0a"):
        assert release_version(value) == value
    for value in ("v1.0.0", "1.0", "01.0.0", "1.0.0-01", "1.0.0+sha.1", "1.0.0-"):
        expect_failure(release_version, value)
    assert build_metadata("1.4.89", "0123456789abcdef", dirty=False) == (
        "build.1.4.89.sha.0123456789ab"
    )
    assert (
        version_with_metadata("0.5.0-beta.5", "1.4.89", "0" * 40, dirty=True)
        == "0.5.0-beta.5+build.1.4.89.sha.000000000000.dirty"
    )
    expect_failure(version_with_metadata, "0.5.0+x", "1.4.89", "a" * 40, dirty=False)
    assert bundle_version_from_commit_count("0") == "1.0.0"
    assert bundle_version_from_commit_count("1489") == "1.14.89"
    assert bundle_version_from_commit_count("20001") == "3.0.1"
    for value in ("1.0.0", "1.14.89", "7", "1.14.89d1", "0.5.0b3", "0.5.0fc2"):
        assert validate_bundle_version(value) == value
    for value in ("500003", "1.0.0d0", "1.0.0d256", "0.5.0beta3", "1.100.0", "1+x"):
        expect_failure(validate_bundle_version, value)
    assert next_development_bundle_version("1.14.89", []) == "1.14.89d1"
    assert (
        next_development_bundle_version(
            "1.14.89", ["1.14.89d2", "1.14.88d9", "1.14.89", "7", "garbage"]
        )
        == "1.14.89d3"
    )
    expect_failure(next_development_bundle_version, "1.14.89d1", [])
    expect_failure(next_development_bundle_version, "1.14.89", ["1.14.89d255"])
    assert executable_version("--check-release", "0.5.0-beta.5") == "0.5.0-beta.5"
    expect_executable_failure("--check-release", "0.5.0-beta.5+build.1")
    assert executable_version("--validate", "1.14.89") == "1.14.89"
    expect_executable_failure("--validate", "0.5.0-beta.5")
    assert executable_version("--next-dev", "1.14.89", "1.14.89d4") == "1.14.89d5"
    expect_executable_failure("--resolve-dext", "0.5.0-beta.5")

    with tempfile.TemporaryDirectory() as directory:
        app = Path(directory) / "app.plist"
        dext = Path(directory) / "dext.plist"
        for path, build in ((app, "1.2.3"), (dext, "1.2.3")):
            path.write_bytes(
                plistlib.dumps(
                    {
                        "CFBundleShortVersionString": "0.5.0-beta.3",
                        "CFBundleVersion": build,
                        "OJDSourceCommit": "a" * 40,
                        "OJDSourceState": "clean",
                    }
                )
            )
        verify_bundle_versions(app, dext, "1.2.3", "0.5.0-beta.3", "a" * 40, "clean")
        for build, short in (("wrong", "0.5.0-beta.3"), ("1.2.3", "0.5.0-beta.4")):
            expect_failure(
                verify_bundle_versions, app, dext, build, short, "a" * 40, "clean"
            )
        version = "0.5.0-beta.3+build.1.2.3.sha.aaaaaaaaaaaa"
        metadata = package_tester.tester_metadata("tester.dmg", version, "1.2.3")
        assert metadata == {
            "artifact": "tester.dmg",
            "version": version,
            "bundle_version": "1.2.3",
            "notarization": "accepted",
            "stapling": "validated",
            "gatekeeper": "accepted",
        }

        repository = Path(directory) / "repository"
        repository.mkdir()
        subprocess.run(["git", "-C", str(repository), "init", "-q"], check=True)
        subprocess.run(
            ["git", "-C", str(repository), "config", "user.name", "Version Test"],
            check=True,
        )
        subprocess.run(
            ["git", "-C", str(repository), "config", "user.email", "test@localhost"],
            check=True,
        )
        tracked = repository / "tracked"
        tracked.write_text("clean\n")
        subprocess.run(["git", "-C", str(repository), "add", "tracked"], check=True)
        subprocess.run(
            ["git", "-C", str(repository), "commit", "-q", "-m", "initial"],
            check=True,
        )
        commit = require_clean_source(repository, "Tester")
        assert source_identity(repository) == (commit, "clean")
        tracked.write_text("dirty\n")
        assert source_identity(repository) == (commit, "dirty")
        expect_failure(require_clean_source, repository, "Tester")
    validate_tester_packaging_flow(fail_after_dmg=False)
    validate_tester_packaging_flow(fail_after_dmg=True)
    return 0


class ReleaseVersioningTests(unittest.TestCase):
    def test_release_versioning_behavior(self) -> None:
        self.assertEqual(main(), 0)
