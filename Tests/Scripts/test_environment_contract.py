import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class EnvironmentContractTests(unittest.TestCase):
    def test_only_root_profile_is_loaded(self):
        source = (ROOT / "scripts/platform/environment.sh").read_text()
        self.assertIn("$PROJECT_DIR/.env.$OJD_ENV", source)
        self.assertNotIn("$SCRIPT_DIR/.env.$OJD_ENV", source)
        self.assertNotIn("$PROJECT_DIR/.env\"", source)

    def test_shared_helper_resolves_repository_root(self):
        result = subprocess.run(
            [
                "/usr/bin/env",
                "bash",
                "-c",
                'source scripts/platform/environment.sh; [[ "$PROJECT_DIR" == "$PWD" ]]',
            ],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_libusb_build_cleanup_does_not_escape_its_function(self):
        source = (ROOT / "scripts/platform/environment.sh").read_text()

        self.assertIn("build_universal_libusb() (", source)
        self.assertIn("trap 'rm -rf \"$tmpdir\"' EXIT", source)
        self.assertNotIn("trap 'rm -rf \"$tmpdir\"' RETURN", source)

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
        sentinel = "must-not-appear-in-audit-output"
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            script = root / "scripts/quality/env-audit.py"
            script.parent.mkdir(parents=True)
            shutil.copy2(ROOT / "scripts/quality/env-audit.py", script)
            (root / ".env.dev").write_text(
                f"CODESIGN_IDENTITY={sentinel}\n", encoding="utf-8"
            )
            (root / ".env.release").write_text(
                f"GUI_CODESIGN_IDENTITY={sentinel}\n", encoding="utf-8"
            )

            result = subprocess.run(
                [sys.executable, str(script)],
                cwd=root,
                check=True,
                capture_output=True,
                text=True,
            )

        self.assertIn("values suppressed", result.stdout)
        self.assertNotIn(sentinel, result.stdout)


if __name__ == "__main__":
    unittest.main()
