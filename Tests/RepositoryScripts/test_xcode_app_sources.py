from __future__ import annotations

import re
import unittest
from pathlib import Path


class XcodeAppSourcesTests(unittest.TestCase):
    root = Path(__file__).resolve().parents[2]

    def test_app_target_compiles_each_swift_file_of_the_app(self) -> None:
        # Shortcuts lists only the App Intents that Xcode compiles into the app,
        # so a file missing here drops its actions without a build error.
        project = (
            self.root / "OpenJoystickDriver.xcodeproj/project.pbxproj"
        ).read_text()
        paths = dict(
            re.findall(
                r"(\w+) /\* [^*]+ \*/ = \{isa = PBXFileReference;.*?path = ([^;]+);",
                project,
            )
        )
        compiled = {
            paths[reference]
            for reference in re.findall(
                r"isa = PBXBuildFile; fileRef = (\w+) /\* [^*]+\.swift \*/", project
            )
        }
        app_sources = {
            str(path.relative_to(self.root))
            for path in (self.root / "Sources/OpenJoystickDriver").rglob("*.swift")
        }
        self.assertEqual(sorted(app_sources - compiled), [])


if __name__ == "__main__":
    unittest.main()
