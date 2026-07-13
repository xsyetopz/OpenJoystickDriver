import pathlib
import subprocess
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class EnvironmentContractTests(unittest.TestCase):
    def test_only_root_profile_is_loaded(self):
        source = (ROOT / "scripts/shared/common.sh").read_text()
        self.assertIn("$PROJECT_DIR/.env.$OJD_ENV", source)
        self.assertNotIn("$SCRIPT_DIR/.env.$OJD_ENV", source)
        self.assertNotIn("$PROJECT_DIR/.env\"", source)

    def test_shared_helper_resolves_repository_root(self):
        result = subprocess.run(
            [
                "/usr/bin/env",
                "bash",
                "-c",
                'source scripts/shared/common.sh; [[ "$PROJECT_DIR" == "$PWD" ]]',
            ],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_legacy_templates_are_removed(self):
        for relative in [
            ".env.example",
            "scripts/.env.dev.example",
            "scripts/.env.release.example",
        ]:
            self.assertFalse((ROOT / relative).exists(), relative)

    def test_release_template_has_one_application_signing_identity(self):
        source = (ROOT / ".env.release.example").read_text()
        self.assertIn("GUI_CODESIGN_IDENTITY", source)
        self.assertNotIn("DAEMON_CODESIGN_IDENTITY", source)
        self.assertNotIn("DAEMON_PROVISIONING_PROFILE", source)

    def test_audit_suppresses_values(self):
        result = subprocess.run(
            [sys.executable, str(ROOT / "scripts/quality/env-audit.py")],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertIn("values suppressed", result.stdout)


if __name__ == "__main__":
    unittest.main()
