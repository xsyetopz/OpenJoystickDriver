from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
OJD = ROOT / "scripts" / "ojd"


class OJDCLITests(unittest.TestCase):
    def run_ojd(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(OJD), *arguments],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )

    def test_help_lists_owned_validation_and_docs_commands(self):
        result = self.run_ojd("--help")

        self.assertEqual(result.returncode, 0)
        self.assertIn("validate scripts", result.stdout)
        self.assertIn("docs export-external-issues", result.stdout)

    def test_unknown_command_is_an_argument_error(self):
        result = self.run_ojd("unknown")

        self.assertEqual(result.returncode, 2)
        self.assertIn("Unknown command: unknown", result.stderr)

    def test_fixed_commands_reject_extra_arguments_before_side_effects(self):
        result = self.run_ojd("build", "dev", "unexpected")

        self.assertEqual(result.returncode, 2)
        self.assertIn("build dev does not accept arguments", result.stderr)

        test_result = self.run_ojd("test", "scripts", "unexpected")
        self.assertEqual(test_result.returncode, 2)
        self.assertIn("test scripts does not accept arguments", test_result.stderr)

        bump_result = self.run_ojd("bump-version")
        self.assertEqual(bump_result.returncode, 2)
        self.assertIn("bump-version requires exactly one argument", bump_result.stderr)


if __name__ == "__main__":
    unittest.main()
