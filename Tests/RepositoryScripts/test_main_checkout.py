from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path

from Scripts.Catalog import generate_controller_catalog as catalog


def git(directory: Path, *arguments: str) -> None:
    subprocess.run(["git", *arguments], cwd=directory, capture_output=True, check=True)


class MainCheckoutTests(unittest.TestCase):
    def linked_worktree(self, directory: str) -> tuple[Path, Path]:
        main = Path(directory).resolve() / "main"
        main.mkdir()
        git(main, "init", "--quiet")
        git(
            main,
            "-c",
            "user.name=t",
            "-c",
            "user.email=t@t",
            "commit",
            "--quiet",
            "--allow-empty",
            "-m",
            "t",
        )
        linked = Path(directory).resolve() / "linked"
        git(main, "worktree", "add", "--quiet", str(linked))
        return main, linked

    def test_a_linked_worktree_names_the_main_checkout(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            main, linked = self.linked_worktree(directory)
            self.assertEqual(catalog.main_checkout_dir(linked), main)
            self.assertEqual(catalog.main_checkout_dir(main), main)

    def test_a_folder_outside_git_is_refused(self) -> None:
        with (
            tempfile.TemporaryDirectory() as directory,
            self.assertRaises(subprocess.CalledProcessError),
        ):
            catalog.main_checkout_dir(Path(directory))

    def test_a_linked_worktree_reads_the_main_checkout_source_cache(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            main, linked = self.linked_worktree(directory)
            self.assertEqual(
                catalog.source_cache(linked), main / ".build" / "catalog-sources"
            )


if __name__ == "__main__":
    unittest.main()
