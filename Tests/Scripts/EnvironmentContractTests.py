import pathlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class EnvironmentContractTests(unittest.TestCase):
    def test_only_root_profile_is_loaded(self):
        source = (ROOT / "scripts/ojd-common.sh").read_text()
        self.assertIn("$PROJECT_DIR/.env.$OJD_ENV", source)
        self.assertNotIn("$SCRIPT_DIR/.env.$OJD_ENV", source)
        self.assertNotIn("$PROJECT_DIR/.env\"", source)

    def test_legacy_templates_are_removed(self):
        for relative in [
            ".env.example",
            "scripts/.env.dev.example",
            "scripts/.env.release.example",
        ]:
            self.assertFalse((ROOT / relative).exists(), relative)

    def test_audit_suppresses_values(self):
        result = subprocess.run(
            [str(ROOT / "scripts/ojd-env-audit.py")],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertIn("values suppressed", result.stdout)


if __name__ == "__main__":
    unittest.main()
