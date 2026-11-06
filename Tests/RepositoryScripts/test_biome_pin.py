from __future__ import annotations

import json
import re
import tempfile
import unittest
from pathlib import Path

from Scripts.Quality.biome_binary import BiomeBinaryError, resolve

ROOT = Path(__file__).resolve().parents[2]


class BiomePinTests(unittest.TestCase):
    def test_package_pin_matches_the_biome_schema_version(self) -> None:
        package = json.loads((ROOT / "package.json").read_text(encoding="utf-8"))
        pin = package["devDependencies"]["@biomejs/biome"]
        self.assertRegex(pin, r"^\d+\.\d+\.\d+$", "the pin must be exact")
        config = json.loads((ROOT / "biome.json").read_text(encoding="utf-8"))
        match = re.fullmatch(
            r"https://biomejs\.dev/schemas/([^/]+)/schema\.json", config["$schema"]
        )
        self.assertIsNotNone(match, config["$schema"])
        assert match is not None
        self.assertEqual(pin, match.group(1))

    def test_the_justfile_runs_the_biome_that_a_linked_worktree_resolves(self) -> None:
        justfile = (ROOT / "justfile").read_text(encoding="utf-8")
        self.assertNotIn("node_modules/.bin/biome", justfile)
        self.assertIn("python3 -m Scripts.Quality.biome_binary", justfile)


def install(root: Path, version: str) -> Path:
    binary = root / "node_modules/.bin/biome"
    binary.parent.mkdir(parents=True)
    binary.write_text(f"console.log('Version: {version}');\n", encoding="utf-8")
    binary.chmod(0o755)
    return binary


class BiomeResolutionTests(unittest.TestCase):
    def checkouts(self, directory: str) -> tuple[Path, Path]:
        main, linked = Path(directory) / "main", Path(directory) / "linked"
        for root in (main, linked):
            root.mkdir()
            (root / "package.json").write_text(
                '{"devDependencies": {"@biomejs/biome": "2.5.15"}}', encoding="utf-8"
            )
        return main, linked

    def test_a_linked_worktree_uses_its_own_binary_first(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            main, linked = self.checkouts(directory)
            install(main, "2.5.15")
            own = install(linked, "2.5.15")
            self.assertEqual(resolve(linked, main), own)

    def test_a_linked_worktree_uses_the_main_checkout_binary(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            main, linked = self.checkouts(directory)
            shared = install(main, "2.5.15")
            self.assertEqual(resolve(linked, main), shared)

    def test_a_version_other_than_the_pin_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            main, linked = self.checkouts(directory)
            install(main, "2.5.14")
            with self.assertRaisesRegex(BiomeBinaryError, "2.5.14.*pins 2.5.15"):
                resolve(linked, main)

    def test_no_binary_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            main, linked = self.checkouts(directory)
            with self.assertRaisesRegex(BiomeBinaryError, "bun install"):
                resolve(linked, main)

    def test_a_folder_outside_git_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            main, _ = self.checkouts(directory)
            install(main, "2.5.15")
            with self.assertRaisesRegex(BiomeBinaryError, "not in a Git checkout"):
                resolve(main)


if __name__ == "__main__":
    unittest.main()
