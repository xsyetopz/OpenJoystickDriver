import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "quality" / "validate-scripts.py"
SPEC = importlib.util.spec_from_file_location("script_layout", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ScriptLayoutTests(unittest.TestCase):
    def make_layout(self, root: Path) -> None:
        scripts = root / "scripts"
        (scripts / "quality").mkdir(parents=True)
        dispatcher = scripts / "ojd"
        dispatcher.write_text(
            '#!/usr/bin/env bash\nexec python3 "$SCRIPT_DIR/quality/check.py"\n'
        )
        dispatcher.chmod(0o755)
        (scripts / "README.md").write_text("# Scripts\n")
        (scripts / "quality" / "check.py").write_text("print('ok')\n")

    def test_common_shell_errors_have_one_owner(self):
        common = (ROOT / "scripts" / "shared" / "common.sh").read_text()
        self.assertIn("die() {", common)
        for relative in [
            "build-tools/build.sh",
            "diagnostics/diagnose.sh",
            "release/notarize.sh",
            "release/package.sh",
        ]:
            implementation = (ROOT / "scripts" / relative).read_text()
            self.assertNotIn("die() {", implementation)

    def test_accepts_owned_non_executable_implementations(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_layout(root)

            self.assertEqual(MODULE.validate_layout(root), [])

    def test_rejects_flat_stale_missing_and_executable_implementations(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_layout(root)
            scripts = root / "scripts"
            (scripts / "legacy.sh").write_text("#!/usr/bin/env bash\n")
            implementation = scripts / "quality" / "check.py"
            implementation.chmod(0o755)
            dispatcher = scripts / "ojd"
            dispatcher.write_text(
                '#!/usr/bin/env bash\n'
                'exec python3 "$SCRIPT_DIR/quality/missing.py"\n'
                '# scripts/' + 'ojd-old.sh\n'
                '# ./' + 'scripts/' + 'quality/check.py\n'
                '# shellcheck ' + 'disable=SC2000\n'
            )

            output = "\n".join(MODULE.validate_layout(root))

            self.assertIn("implementation must have an owner directory", output)
            self.assertIn("only scripts/ojd may be executable", output)
            self.assertIn("routed implementation does not exist", output)
            self.assertIn("stale flat script path", output)
            self.assertIn("invoke scripts/ojd", output)
            self.assertIn("ShellCheck suppression directives are forbidden", output)


if __name__ == "__main__":
    unittest.main()
