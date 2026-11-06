from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from Scripts.Command.execution import PROJECT_DIR, swift_command

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
            other = stub(root / "other/swift", PINNED)
            env = {
                **os.environ,
                "DEVELOPER_DIR": str(root / "Developer"),
                "PATH": f"{other.parent}:{os.environ['PATH']}",
            }
            env.pop("SDKROOT", None)
            result = subprocess.run(
                swift_command(["build", "--show-bin-path"]),
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


if __name__ == "__main__":
    unittest.main()
