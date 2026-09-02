"""Behavior self-test for release version and package metadata helpers."""

from __future__ import annotations

import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from bundle_version import (
    dext_bundle_version_from_semver,
    resolve_dext_bundle_version,
    tester_bundle_version,
    validate_dext_bundle_version,
)
from package_common import verify_bundle_versions
from package_tester import tester_metadata


def expect_failure(callable_, *args, **kwargs) -> None:
    try:
        callable_(*args, **kwargs)
    except SystemExit:
        return
    raise AssertionError(f"expected failure from {callable_.__name__}")


def executable_version(*args: str) -> str:
    result = subprocess.run(
        [sys.executable, str(SCRIPT_DIR / "bundle_version.py"), *args],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode:
        raise AssertionError(result.stderr)
    return result.stdout.strip()


def expect_executable_failure(*args: str) -> None:
    result = subprocess.run(
        [sys.executable, str(SCRIPT_DIR / "bundle_version.py"), *args],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode == 0:
        raise AssertionError(f"expected executable failure for {args}")


def main() -> int:
    assert dext_bundle_version_from_semver("0.5.0-beta.3") == "0.5.0b3"
    assert dext_bundle_version_from_semver("1.2.3-alpha.1") == "1.2.3a1"
    assert dext_bundle_version_from_semver("1.2.3-rc.2") == "1.2.3fc2"
    for value in ("0.5.0", "0.5.0a1", "0.5.0b3", "0.5.0fc2"):
        assert validate_dext_bundle_version(value) == value
    assert (
        resolve_dext_bundle_version("0.5.0-beta.3", "0.5.0b3", release=True)
        == "0.5.0b3"
    )
    expect_failure(resolve_dext_bundle_version, "0.5.0-beta.3", "0.5.0b2", release=True)
    for value in ("500003", "0.5.0b0", "0.5.0b256", "0.5.0beta3", "1.100.0"):
        expect_failure(validate_dext_bundle_version, value)
    assert (
        executable_version("--resolve-dext", "0.5.0-beta.3", "0.5.0b3", "--release")
        == "0.5.0b3"
    )
    assert executable_version("--resolve-dext", "0.5.0-beta.3", "0.5.0b2") == "0.5.0b2"
    expect_executable_failure("--resolve-dext", "0.5.0-beta.3", "0.5.0b2", "--release")
    for value in ("1.2.3-beta.1.2", "1.2.3-beta.0", "1.2.3-beta", "1.2.3+meta"):
        expect_failure(dext_bundle_version_from_semver, value)
    for value in ("65536.0.0", "1.100.0", "1.2.100", "1.2.3-beta.256"):
        expect_failure(dext_bundle_version_from_semver, value)

    with tempfile.TemporaryDirectory() as directory:
        state = Path(directory) / "tester-state"
        assert tester_bundle_version("1.2.3", state).endswith("d1")
        assert tester_bundle_version("1.2.3", state).endswith("d2")
        assert tester_bundle_version("1.2.4", state).endswith("d1")

        app = Path(directory) / "app.plist"
        dext = Path(directory) / "dext.plist"
        for path, build in ((app, "1.2.3d1"), (dext, "0.5.0b3")):
            path.write_bytes(
                plistlib.dumps(
                    {
                        "CFBundleShortVersionString": "0.5.0-beta.3",
                        "CFBundleVersion": build,
                    }
                )
            )
        verify_bundle_versions(app, dext, "1.2.3d1", "0.5.0b3", "0.5.0-beta.3")
        expect_failure(
            verify_bundle_versions, app, dext, "wrong", "0.5.0b3", "0.5.0-beta.3"
        )
        metadata = tester_metadata("tester.dmg", "0.5.0-beta.3", "1.2.3d1", "0.5.0b3")
        assert metadata == {
            "artifact": "tester.dmg",
            "version": "0.5.0-beta.3",
            "app_bundle_build_version": "1.2.3d1",
            "dext_bundle_version": "0.5.0b3",
        }
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
