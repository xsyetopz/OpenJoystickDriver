import importlib.util
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "ojd-validate-swift-structure.py"
SPEC = importlib.util.spec_from_file_location("swift_structure", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class SwiftStructureTests(unittest.TestCase):
    def test_accepts_owned_layout(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "Sources" / "Example" / "Foo"
            tests = root / "Tests" / "ExampleTests" / "Foo"
            source.mkdir(parents=True)
            tests.mkdir(parents=True)
            (source / "Foo.swift").write_text("struct Foo {}\n")
            (tests / "FooTests.swift").write_text("struct FooTests {}\n")

            errors, _ = MODULE.validate(root)

            self.assertEqual(errors, [])

    def test_rejects_limits_suppressions_flat_tests_and_duplicate_basenames(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "Sources" / "Example"
            nested = source / "Nested"
            tests = root / "Tests" / "OpenJoystickDriverKitTests"
            source.mkdir(parents=True)
            nested.mkdir()
            tests.mkdir(parents=True)
            (source / "Foo+Bar.swift").write_text(
                "// swiftlint:disable line_length\n" + "\n" * 800
            )
            (source / "Same.swift").write_text("struct Same {}\n")
            (nested / "Same.swift").write_text("extension Same {}\n")
            (tests / "FlatTests.swift").write_text("struct FlatTests {}\n")

            errors, _ = MODULE.validate(root)
            output = "\n".join(errors)

            self.assertIn("exceeds 800", output)
            self.assertIn("ownership directory", output)
            self.assertIn("suppression directives are forbidden", output)
            self.assertIn("tests must be placed by source ownership", output)
            self.assertIn("duplicate Swift basename Same.swift", output)


if __name__ == "__main__":
    unittest.main()
