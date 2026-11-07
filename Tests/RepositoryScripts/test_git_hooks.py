from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path


class GitHookTests(unittest.TestCase):
    root = Path(__file__).resolve().parents[2]
    pre_push = root / "Scripts/Quality/check-pushed-tips.sh"
    zero_oid = "0" * 40

    def git(self, repository: Path, *arguments: str) -> str:
        result = subprocess.run(
            ["git", *arguments],
            cwd=repository,
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout.strip()

    def test_pre_push_checks_outgoing_tree_without_running_full_validation(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory)
            self.git(repository, "init", "--quiet")
            self.git(repository, "config", "user.name", "Hook Test")
            self.git(repository, "config", "user.email", "hook@example.invalid")
            (repository / "example.txt").write_text("valid\n")
            self.git(repository, "add", "example.txt")
            self.git(repository, "commit", "--quiet", "-m", "valid")
            valid = self.git(repository, "rev-parse", "HEAD")

            valid_result = subprocess.run(
                ["bash", str(self.pre_push)],
                cwd=repository,
                input=f"refs/heads/topic {valid} refs/heads/topic {self.zero_oid}\n",
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(valid_result.returncode, 0)

            (repository / "example.txt").write_text("trailing whitespace \n")
            self.git(repository, "add", "example.txt")
            self.git(repository, "commit", "--quiet", "-m", "invalid")
            invalid = self.git(repository, "rev-parse", "HEAD")
            invalid_result = subprocess.run(
                ["bash", str(self.pre_push)],
                cwd=repository,
                input=f"refs/heads/topic {invalid} refs/heads/topic {valid}\n",
                capture_output=True,
                text=True,
                check=False,
            )

        self.assertNotEqual(invalid_result.returncode, 0)
        self.assertIn("trailing whitespace", invalid_result.stdout)
