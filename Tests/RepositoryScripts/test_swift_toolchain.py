from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from Scripts.Platform.swift_sdk import FOUNDATION_MODULE

PROJECT_DIR = Path(__file__).resolve().parents[2]
WITH_ENV = str(PROJECT_DIR / "Scripts/with-env.sh")

PINNED = (PROJECT_DIR / ".swift-version").read_text(encoding="utf-8").strip()


def stub(path: Path, version: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        f'#!/bin/sh\n[ "$1" = --version ] && echo "Apple Swift version {version} (stub)" && exit 0\n'
        'echo "ran:$0:$*"\n',
        encoding="utf-8",
    )
    path.chmod(0o755)
    return path


class SwiftToolchainTests(unittest.TestCase):
    def run_swift(
        self, xcode_version: str
    ) -> tuple[subprocess.CompletedProcess[str], Path]:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            xcode = stub(
                root / "Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift",
                xcode_version,
            )
            stub(root / "Developer/usr/bin/xcodebuild", xcode_version)
            other = stub(root / "other/swift", PINNED)
            env = {
                **os.environ,
                "DEVELOPER_DIR": str(root / "Developer"),
                "PATH": f"{other.parent}:{os.environ['PATH']}",
            }
            env.pop("SDKROOT", None)
            result = subprocess.run(
                [WITH_ENV, "swift", "build", "--show-bin-path"],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
        return result, xcode

    def test_swift_command_runs_the_swift_of_the_xcode_toolchain(self) -> None:
        result, xcode = self.run_swift(PINNED)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), f"ran:{xcode}:build --show-bin-path")

    def test_an_xcode_swift_newer_than_the_pinned_version_runs(self) -> None:
        result, xcode = self.run_swift("99.0.1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), f"ran:{xcode}:build --show-bin-path")

    def test_an_xcode_swift_older_than_the_pinned_version_stops(self) -> None:
        result, _ = self.run_swift("6.3")
        self.assertEqual(result.returncode, 2)
        self.assertIn(".swift-version", result.stderr)
        self.assertNotIn("ran:", result.stdout)

    def run_without_xcode(self, path: list[Path]) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            module = root / "Developer/SDKs/MacOSX26.sdk" / FOUNDATION_MODULE
            module.mkdir(parents=True)
            (module / "arm64e-apple-macos.swiftinterface").write_text(
                f"// swift-compiler-version: Apple Swift version {PINNED}\n",
                encoding="utf-8",
            )
            # /usr/bin/python3 asks xcrun for the developer folder, which this stub lacks.
            tools = root / "tools"
            tools.mkdir()
            (tools / "python3").symlink_to(sys.executable)
            folders = [str(folder.parent) for folder in path] + [str(tools)]
            env = {
                **os.environ,
                "DEVELOPER_DIR": str(root / "Developer"),
                "HOME": str(root / "home"),
                "PATH": ":".join([*folders, "/usr/bin", "/bin", "/usr/sbin", "/sbin"]),
            }
            env.pop("SDKROOT", None)
            return subprocess.run(
                [WITH_ENV, "swift", "build", "--show-bin-path"],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

    def test_without_xcode_a_swift_org_toolchain_runs(self) -> None:
        # Arrange
        with tempfile.TemporaryDirectory() as directory:
            toolchain = stub(Path(directory) / "toolchain/swift", PINNED)

            # Act
            result = self.run_without_xcode([toolchain])

        # Assert
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.strip(), f"ran:{toolchain}:build --show-bin-path"
        )

    def test_without_xcode_the_system_swift_stops(self) -> None:
        # Act
        result = self.run_without_xcode([])

        # Assert
        self.assertEqual(result.returncode, 2)
        self.assertIn("swift.org toolchain", result.stderr)
        self.assertNotIn("ran:", result.stdout)


if __name__ == "__main__":
    unittest.main()
