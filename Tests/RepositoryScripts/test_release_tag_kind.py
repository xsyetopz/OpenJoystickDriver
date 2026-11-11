"""Behavior tests for the release tag grammar, tester builds included."""

from __future__ import annotations

import re
import subprocess
import sys
import unittest
from pathlib import Path

from Scripts.Release.bundle_version import release_tag_kind, tester_base_tag

PROJECT_DIR = Path(__file__).resolve().parents[2]


def expect_failure(callable_, tag: str) -> None:
    try:
        callable_(tag)
    except SystemExit:
        return
    raise AssertionError(f"expected {tag} to be refused")


class ReleaseTagKindTests(unittest.TestCase):
    def test_kinds(self) -> None:
        self.assertEqual(release_tag_kind("0.6.0"), "release")
        self.assertEqual(release_tag_kind("0.6.0-alpha.3"), "prerelease")
        self.assertEqual(release_tag_kind("0.6.0-rc.1"), "prerelease")
        self.assertEqual(release_tag_kind("0.6.0-alpha.2.tester.1"), "tester")
        self.assertEqual(release_tag_kind("0.5.1-tester.4"), "tester")

    def test_refused_tags(self) -> None:
        for tag in (
            "v0.6.0",
            "0.6.0-alpha.0",
            "0.6.0-alpha.2.tester.0",
            "0.6.0-alpha.2.tester.01",
            "0.6.0-tester.1",
            "0.6.0-alpha.2.tester",
            "0.6.0-alpha.2.tester.1.tester.2",
            "0.6.0-alpha.2.tester.1+build.1",
            "0.6.0-nightly.1",
        ):
            with self.subTest(tag=tag):
                expect_failure(release_tag_kind, tag)

    def test_base_tag_is_the_release_before_the_tester_build(self) -> None:
        self.assertEqual(tester_base_tag("0.6.0-alpha.2.tester.1"), "0.6.0-alpha.2")
        self.assertEqual(tester_base_tag("0.6.0-rc.1.tester.12"), "0.6.0-rc.1")
        self.assertEqual(tester_base_tag("0.5.1-tester.2"), "0.5.0")
        self.assertEqual(tester_base_tag("1.0.1-tester.1"), "1.0.0")

    def test_a_tag_that_is_not_a_tester_build_has_no_base_tag(self) -> None:
        for tag in ("0.6.0-tester.1", "0.6.0-alpha.3", "0.6.0"):
            with self.subTest(tag=tag):
                expect_failure(tester_base_tag, tag)

    def test_command_line(self) -> None:
        for args, expected in (
            (["--tag-kind", "0.6.0-alpha.2.tester.1"], "tester"),
            (["--tag-kind", "0.6.0-alpha.3"], "prerelease"),
            (["--tester-base", "0.6.0-alpha.2.tester.1"], "0.6.0-alpha.2"),
        ):
            result = subprocess.run(
                [sys.executable, "-m", "Scripts.Release.bundle_version", *args],
                cwd=PROJECT_DIR,
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), expected)

    def test_workflow_uses_the_tag_check(self) -> None:
        workflow = (PROJECT_DIR / ".github/workflows/release.yml").read_text()
        self.assertIn("bundle_version --tag-kind", workflow)
        self.assertIn("bundle_version --tester-base", workflow)
        self.assertIsNone(re.search(r"\(alpha\|beta\|rc\)", workflow))


if __name__ == "__main__":
    unittest.main()
