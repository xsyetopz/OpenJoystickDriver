import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

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
        self.assertIn("check scripts", result.stdout)
        self.assertIn("check driverkit", result.stdout)
        self.assertIn("driverkit generate", result.stdout)
        self.assertIn("docs export-external-issues", result.stdout)

    def test_unknown_command_is_an_argument_error(self):
        result = self.run_ojd("unknown")

        self.assertEqual(result.returncode, 2)

    def test_fixed_commands_reject_extra_arguments_before_side_effects(self):
        result = self.run_ojd("build", "dev", "unexpected")

        self.assertEqual(result.returncode, 2)

        test_result = self.run_ojd("test", "scripts", "unexpected")
        self.assertEqual(test_result.returncode, 2)

        bump_result = self.run_ojd("bump-version")
        self.assertEqual(bump_result.returncode, 2)

    def test_canonical_build_routes_preserve_legacy_validation(self):
        install = self.run_ojd("build", "install", "dev", "unexpected")
        self.assertEqual(install.returncode, 2)

        install_fast = self.run_ojd("build", "install-fast", "dev", "unexpected")
        self.assertEqual(install_fast.returncode, 2)

        legacy = self.run_ojd("rebuild", "dev", "unexpected")
        self.assertEqual(legacy.returncode, 2)

    def test_canonical_release_routes_preserve_legacy_validation(self):
        bump = self.run_ojd("release", "bump-version")
        self.assertEqual(bump.returncode, 2)

        package = self.run_ojd("release", "package", "one", "two")
        self.assertEqual(package.returncode, 2)

        install = self.run_ojd("release", "install-local", "one", "two")
        self.assertEqual(install.returncode, 2)

        notarize = self.run_ojd("release", "notarize", "log")
        self.assertEqual(notarize.returncode, 2)

        legacy = self.run_ojd("package", "release", "one", "two")
        self.assertEqual(legacy.returncode, 2)

    def test_unknown_canonical_nested_commands_are_argument_errors(self):
        build = self.run_ojd("build", "install", "unknown")
        self.assertEqual(build.returncode, 2)

        release = self.run_ojd("release", "unknown")
        self.assertEqual(release.returncode, 2)

    def test_record_diagnostic_uses_universal_libusb_for_swiftpm(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            scripts = project / "scripts"
            platform = scripts / "platform"
            platform.mkdir(parents=True)
            shutil.copy2(OJD, scripts / "ojd")
            shutil.copy2(
                ROOT / "scripts" / "platform" / "environment.sh",
                platform / "environment.sh",
            )

            libusb_cache = project / ".build" / "libusb-universal"
            (libusb_cache / "lib").mkdir(parents=True)
            (libusb_cache / "lib" / "libusb-1.0.a").touch()

            record = project / "controller.json"
            record.write_text("{}\n")
            swift = project / "fake-swift"
            swift.write_text(
                "#!/usr/bin/env bash\n"
                "printf 'PKG_CONFIG_PATH=%s\\n' \"$PKG_CONFIG_PATH\"\n"
                "printf 'OJD_USE_LOCAL_SWIFTUSB=%s\\n' \"$OJD_USE_LOCAL_SWIFTUSB\"\n"
                "printf 'ARG=%s\\n' \"$@\"\n"
            )
            swift.chmod(0o755)

            environment = os.environ.copy()
            environment["SWIFT_BIN"] = str(swift)
            environment.pop("PKG_CONFIG_PATH", None)
            result = subprocess.run(
                [
                    str(scripts / "ojd"),
                    "diagnose",
                    "record",
                    str(record),
                    "--validate-only",
                ],
                cwd=project,
                env=environment,
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(
                f"Universal libusb cache hit: {libusb_cache / 'lib' / 'libusb-1.0.a'}",
                result.stdout,
            )
            self.assertIn(f"PKG_CONFIG_PATH={libusb_cache}", result.stdout)
            self.assertIn("OJD_USE_LOCAL_SWIFTUSB=1", result.stdout)
            self.assertIn("ARG=run", result.stdout)
            self.assertIn("ARG=OpenJoystickDriverHIDTool", result.stdout)
            self.assertIn(f"ARG={record}", result.stdout)
            self.assertIn("ARG=--validate-only", result.stdout)
            pkg_config = libusb_cache / "libusb-1.0.pc"
            self.assertTrue(pkg_config.is_file())
            self.assertIn(f"prefix={libusb_cache}", pkg_config.read_text())

    def test_swiftpm_repair_uses_package_clean(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            scripts = project / "scripts"
            scripts.mkdir()
            shutil.copy2(OJD, scripts / "ojd")

            build = project / ".build"
            build.mkdir()
            invocation = project / "swift-package-invocation"
            swift_package = project / "fake-swift-package"
            swift_package.write_text(
                f"#!/usr/bin/env bash\nprintf '%s\\n' \"$@\" > {invocation}\n"
            )
            swift_package.chmod(0o755)

            environment = os.environ.copy()
            environment["SWIFT_PACKAGE_BIN"] = str(swift_package)

            result = subprocess.run(
                [str(scripts / "ojd"), "repair", "swiftpm-module-cache"],
                cwd=project,
                env=environment,
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(invocation.read_text(), "clean\n")


if __name__ == "__main__":
    unittest.main()
