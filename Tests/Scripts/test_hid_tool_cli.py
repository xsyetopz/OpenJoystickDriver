import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / ".build" / "debug" / "OpenJoystickDriverHIDTool"


class HIDToolCLITests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        result = subprocess.run(
            ["swift", "build", "--product", "OpenJoystickDriverHIDTool"],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            raise AssertionError(result.stderr or result.stdout)

    def run_tool(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(BINARY), *arguments],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )

    def test_help_identifies_internal_supported_entrypoint(self):
        for option in ("-h", "--help"):
            result = self.run_tool(option)
            self.assertEqual(result.returncode, 0)
            self.assertIn("internal hardware diagnostic utility", result.stderr)
            self.assertIn("./scripts/ojd diagnose", result.stderr)

    def test_unknown_option_is_rejected(self):
        result = self.run_tool("--list", "--unknown")
        self.assertEqual(result.returncode, 2)
        self.assertIn("unknown option '--unknown'", result.stderr)

    def test_multiple_modes_are_rejected(self):
        result = self.run_tool("--list", "--monitor")
        self.assertEqual(result.returncode, 2)
        self.assertIn("multiple mode selectors", result.stderr)

    def test_malformed_and_out_of_range_values_are_rejected(self):
        malformed = self.run_tool("--monitor", "--seconds", "nope")
        self.assertEqual(malformed.returncode, 2)
        self.assertIn("malformed value 'nope' for '--seconds'", malformed.stderr)

        out_of_range = self.run_tool("--monitor", "--seconds", "61")
        self.assertEqual(out_of_range.returncode, 2)
        self.assertIn(
            "value for '--seconds' is out of range 1...60", out_of_range.stderr
        )

    def test_mode_ownership_and_duplicates_are_rejected(self):
        misplaced = self.run_tool("--list", "--seconds", "10")
        self.assertEqual(misplaced.returncode, 2)
        self.assertIn("option '--seconds' is not valid with '--list'", misplaced.stderr)

        duplicate = self.run_tool("--monitor", "--seconds", "10", "--seconds", "20")
        self.assertEqual(duplicate.returncode, 2)
        self.assertIn("duplicate option '--seconds'", duplicate.stderr)


if __name__ == "__main__":
    unittest.main()
