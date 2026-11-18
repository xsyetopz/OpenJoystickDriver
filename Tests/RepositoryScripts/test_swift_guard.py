from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest import mock

from Scripts.Quality import swift_guard
from Scripts.Quality.swift_guard import (
    STRICT_SETTINGS,
    manifest_problems,
    project_problems,
    source_problems,
    suppressions,
)

ROOT = Path(__file__).resolve().parents[2]


def setting(name: str) -> dict[str, object]:
    key, _, argument = name.partition(":")
    return {"tool": "swift", "kind": {key: {"_0": argument} if argument else {}}}


def package(*targets: dict[str, object]) -> dict[str, object]:
    return {
        "toolsVersion": {"_version": "6.4.0"},
        "swiftLanguageModes": ["6"],
        "targets": list(targets),
    }


def strict_target(name: str, *extra: str) -> dict[str, object]:
    names = [*STRICT_SETTINGS, *extra]
    return {"name": name, "type": "regular", "settings": [setting(n) for n in names]}


class ManifestTests(unittest.TestCase):
    def test_a_strict_package_passes(self) -> None:
        self.assertEqual(manifest_problems(package(strict_target("Core"))), [])

    def test_a_target_without_strict_memory_safety_is_reported(self) -> None:
        # Arrange
        target = strict_target("Core")
        target["settings"] = [
            entry
            for entry in target["settings"]
            if "strictMemorySafety" not in entry["kind"]
        ]

        # Act
        problems = manifest_problems(package(target))

        # Assert
        self.assertEqual(len(problems), 1)
        self.assertIn("target Core lacks strictMemorySafety", problems[0])

    def test_unsafe_flags_are_reported(self) -> None:
        problems = manifest_problems(package(strict_target("Core", "unsafeFlags")))
        self.assertTrue(any("uses unsafeFlags" in problem for problem in problems))

    def test_old_tools_and_language_modes_are_reported(self) -> None:
        # Arrange
        manifest = package()
        manifest["toolsVersion"] = {"_version": "6.0.0"}
        manifest["swiftLanguageModes"] = ["5", "6"]

        # Act
        problems = manifest_problems(manifest)

        # Assert
        self.assertEqual(len(problems), 2)

    def test_plugin_targets_are_skipped(self) -> None:
        plugin = {"name": "Plugin", "type": "plugin", "settings": []}
        self.assertEqual(manifest_problems(package(plugin)), [])


class SourceTests(unittest.TestCase):
    def test_xctest_outside_ui_tests_is_reported(self) -> None:
        problems = source_problems(
            "Tests/CoreTests/A.swift", "@testable import XCTest\n"
        )
        self.assertEqual(len(problems), 1)
        self.assertIn("imports XCTest", problems[0])

    def test_xctest_in_ui_tests_passes(self) -> None:
        self.assertEqual(
            source_problems("Tests/AppUITests/A.swift", "import XCTest\n"), []
        )

    def test_a_disable_with_a_matching_enable_passes(self) -> None:
        text = "// swiftlint:disable a b\nlet x = 1\n// swiftlint:enable b a\n"
        self.assertEqual(suppressions(text), [])

    def test_a_disable_to_the_end_of_the_file_is_reported(self) -> None:
        text = "let y = 0\n// swiftlint:disable a b\n// swiftlint:enable a\n"
        self.assertEqual(len(suppressions(text)), 1)
        self.assertTrue(suppressions(text)[0].startswith("2: "))

    def test_disable_next_passes(self) -> None:
        self.assertEqual(suppressions("// swiftlint:disable:next a\nlet x = 1\n"), [])

    def test_swift_format_ignore_file_is_reported(self) -> None:
        self.assertEqual(len(suppressions("// swift-format-ignore-file\n")), 1)


class ProjectTests(unittest.TestCase):
    def test_a_project_without_the_base_xcconfig_is_reported(self) -> None:
        problems = project_problems("App.xcodeproj/project.pbxproj", "")
        self.assertIn("Config/Base.xcconfig", problems[0])

    def test_overrides_are_reported_once(self) -> None:
        # Arrange
        pbxproj = (
            "/* Config/Base.xcconfig */\n"
            "\t\tSWIFT_VERSION = 5.0;\n\t\tSWIFT_VERSION = 5.0;\n"
            '\t\tOTHER_SWIFT_FLAGS = "-DDEBUG";\n'
        )

        # Act
        problems = project_problems("App.xcodeproj/project.pbxproj", pbxproj)

        # Assert
        self.assertEqual(len(problems), 2)


class ScanTests(unittest.TestCase):
    def test_foreign_tools_are_reported(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            # Arrange
            root = Path(directory)
            (root / "Podfile").touch()

            # Act
            problems = swift_guard.scan(root, [])

            # Assert
            self.assertEqual(len(problems), 1)
            self.assertIn("CocoaPods", problems[0])

    def test_the_repository_passes(self) -> None:
        # Arrange
        swift_files = swift_guard.tracked_swift_files(ROOT)

        # Act
        with mock.patch.object(
            swift_guard, "dump_package", return_value=package(strict_target("Core"))
        ):
            problems = swift_guard.scan(ROOT, swift_files)

        # Assert
        self.assertEqual(problems, [])


if __name__ == "__main__":
    unittest.main()
