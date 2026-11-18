from __future__ import annotations

import unittest
from pathlib import Path

from Scripts.Quality.compile_commands import (
    clang_target_entries,
    language_flags,
    top_level_projects,
)


class CompileCommandsTests(unittest.TestCase):
    def test_flags_follow_the_source_language(self) -> None:
        self.assertEqual(language_flags("a.c", "c++20"), ["clang", "-std=c17"])
        self.assertEqual(language_flags("a.m", "c++20"), ["clang", "-fobjc-arc"])
        self.assertEqual(
            language_flags("a.mm", "c++20"), ["clang++", "-std=c++20", "-fobjc-arc"]
        )
        self.assertEqual(language_flags("a.cpp", "c++23"), ["clang++", "-std=c++23"])

    def test_nested_xmake_projects_are_skipped(self) -> None:
        manifests = [
            "Tools/Probe/xmake.lua",
            "Tools/Probe/Sub/xmake.lua",
            "Other/xmake.lua",
        ]
        self.assertEqual(top_level_projects(manifests), ["Tools/Probe", "Other"])

    def test_a_root_project_covers_every_nested_one(self) -> None:
        self.assertEqual(top_level_projects(["xmake.lua", "Tools/xmake.lua"]), [""])

    def test_clang_targets_get_one_entry_per_source(self) -> None:
        # Arrange
        root = Path("/repo")
        description = {
            "cxx_language_standard": "c++20",
            "targets": [
                {
                    "module_type": "SwiftTarget",
                    "path": "Sources/App",
                    "sources": ["a.swift"],
                },
                {
                    "module_type": "ClangTarget",
                    "path": "Sources/Bridge",
                    "sources": ["b.mm"],
                },
            ],
        }

        # Act
        entries = clang_target_entries(root, description, "/tc/usr/lib/swift", "/sdk")

        # Assert
        self.assertEqual(len(entries), 1)
        arguments = entries[0]["arguments"]
        self.assertEqual(entries[0]["file"], "/repo/Sources/Bridge/b.mm")
        self.assertEqual(
            arguments[:5], ["clang++", "-std=c++20", "-fobjc-arc", "-isysroot", "/sdk"]
        )
        self.assertIn("/repo/Sources/Bridge/include", arguments)
        self.assertEqual(arguments[-2:], ["-c", "/repo/Sources/Bridge/b.mm"])


if __name__ == "__main__":
    unittest.main()
