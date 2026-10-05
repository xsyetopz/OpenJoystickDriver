from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from Scripts.Command import dispatcher
from Scripts.Documentation.wiki import publish

IDENTITY = {
    "GIT_AUTHOR_NAME": "Test",
    "GIT_AUTHOR_EMAIL": "test@example.com",
    "GIT_COMMITTER_NAME": "Test",
    "GIT_COMMITTER_EMAIL": "test@example.com",
}


class TargetInvoked(Exception):
    pass


def git(*arguments: str, cwd: Path) -> str:
    return subprocess.run(
        ["git", *arguments], cwd=cwd, check=True, capture_output=True, text=True
    ).stdout


class WikiPublishTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        base = Path(self.temporary.name)
        self.root = base / "repository"
        (self.root / "wiki").mkdir(parents=True)
        (self.root / "wiki" / "Home.md").write_text("# Home\n", encoding="utf-8")
        self.bare = base / "remote.git"
        git("init", "-q", "--bare", str(self.bare), cwd=base)
        self.remote = self.bare.as_uri()
        patcher = patch.dict(os.environ, IDENTITY)
        patcher.start()
        self.addCleanup(patcher.stop)

    def run_publish(self, remote: str | None = None, dry_run: bool = False) -> str:
        return publish.publish(
            self.root, remote or self.remote, "owner/name", "abc123", "main", dry_run
        )

    def remote_files(self) -> list[str]:
        return git("ls-tree", "--name-only", "HEAD", cwd=self.bare).split()

    def test_publish_writes_pages_then_reports_current(self) -> None:
        self.assertIn("Published", self.run_publish())
        self.assertEqual(self.remote_files(), ["Home.md"])
        self.assertIn("abc123", git("log", "-1", "--format=%s", cwd=self.bare))
        self.assertEqual(self.run_publish(), "The wiki is current.")

    def test_publish_removes_deleted_pages(self) -> None:
        (self.root / "wiki" / "Extra.md").write_text("# Extra\n", encoding="utf-8")
        self.run_publish()
        (self.root / "wiki" / "Extra.md").unlink()
        self.run_publish()
        self.assertEqual(self.remote_files(), ["Home.md"])

    def test_dry_run_does_not_push(self) -> None:
        message = self.run_publish(dry_run=True)
        self.assertIn("Home.md", message)
        self.assertEqual(
            subprocess.run(
                ["git", "rev-parse", "--verify", "HEAD"],
                cwd=self.bare,
                capture_output=True,
                check=False,
            ).returncode,
            128,
        )

    def test_missing_remote_explains_how_to_create_the_wiki(self) -> None:
        missing = (self.bare.parent / "absent.git").as_uri()
        with self.assertRaises(publish.PublishError) as caught:
            self.run_publish(remote=missing)
        self.assertIn("https://github.com/owner/name/wiki", str(caught.exception))

    def test_credentials_are_redacted(self) -> None:
        self.assertNotIn("secret", publish.redact("fatal: https://x:secret@host/a"))

    def test_origin_protocol_is_kept(self) -> None:
        git("init", "-q", cwd=self.root)
        git("remote", "add", "origin", "git@github.com:owner/name.git", cwd=self.root)
        self.assertEqual(
            publish.origin_wiki(self.root),
            ("git@github.com:owner/name.wiki.git", "owner/name"),
        )
        git(
            "remote",
            "set-url",
            "origin",
            "https://github.com/owner/name",
            cwd=self.root,
        )
        self.assertEqual(
            publish.origin_wiki(self.root)[0], "https://github.com/owner/name.wiki.git"
        )

    def test_source_label_marks_uncommitted_wiki_changes(self) -> None:
        git("init", "-q", cwd=self.root)
        git("add", "-A", cwd=self.root)
        git("commit", "-q", "-m", "init", cwd=self.root)
        commit = git("rev-parse", "HEAD", cwd=self.root).strip()
        self.assertEqual(publish.source_label(self.root), commit)
        (self.root / "wiki" / "Home.md").write_text("# Changed\n", encoding="utf-8")
        self.assertEqual(publish.source_label(self.root), f"{commit}-dirty")

    def test_dispatcher_routes_publish_wiki(self) -> None:
        with (
            patch.object(
                dispatcher, "exec_target", side_effect=TargetInvoked
            ) as execute,
            self.assertRaises(TargetInvoked),
        ):
            dispatcher.dispatch(["docs", "publish-wiki", "--dry-run"])
        execute.assert_called_once_with(
            "Documentation/wiki/publish.py", ["--dry-run"], python=True
        )


if __name__ == "__main__":
    unittest.main()
