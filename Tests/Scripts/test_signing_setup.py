import hashlib
import os
import pathlib
import plistlib
import subprocess
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]


def write_profile(path: pathlib.Path, name: str) -> None:
    path.write_bytes(
        plistlib.dumps(
            {
                "Name": name,
                "TeamIdentifier": ["ABCDEF1234"],
                "Entitlements": {
                    "com.apple.developer.hid.virtual.device": True,
                    "com.apple.developer.team-identifier": "ABCDEF1234",
                    "com.apple.developer.driverkit.userclient-access": [
                        "com.openjoystickdriver.VirtualHIDDevice"
                    ],
                },
            }
        )
    )


class SigningSetupTests(unittest.TestCase):
    def test_profile_certificate_verification_cleanup_is_subshell_scoped(self):
        tooling = (ROOT / "scripts/platform/environment.sh").read_text()
        start = tooling.index("verify_profile_cert() (")
        end = tooling.index("\n)\n", start)
        function = tooling[start:end]

        self.assertIn("trap 'rm -f \"$tmpder\"' EXIT", function)
        self.assertNotIn(" RETURN", function)

    def test_profile_installer_requires_only_development_assets(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            source = root / "Profiles"
            source.mkdir()
            (source / "OpenJoystickDriver.provisionprofile").write_text("host")
            (source / "OpenJoystickDriver_VirtualHIDDevice.provisionprofile").write_text(
                "driver"
            )
            environment = os.environ.copy()
            environment["HOME"] = str(root / "home")

            result = subprocess.run(
                [
                    "/usr/bin/env",
                    "bash",
                    str(ROOT / "scripts/signing/signing.sh"),
                    "install-profiles",
                    str(source),
                ],
                cwd=ROOT,
                env=environment,
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            installed = root / "home/Library/MobileDevice/Provisioning Profiles"
            self.assertTrue((installed / "OpenJoystickDriver.provisionprofile").is_file())
            self.assertTrue(
                (installed / "OpenJoystickDriver_VirtualHIDDevice.provisionprofile").is_file()
            )
            self.assertFalse((installed / "OpenJoystickDriver_DevID.provisionprofile").exists())
            self.assertIn("Skipping optional publisher release profile", result.stdout)

    def test_configurator_writes_development_env_without_release_profile(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            fake_security = bin_dir / "security"
            fake_security.write_text(
                "#!/usr/bin/env bash\n"
                "if [[ \"$1\" == cms ]]; then cat \"${@: -1}\"; exit 0; fi\n"
                "exit 1\n"
            )
            fake_security.chmod(0o755)
            host = root / "OpenJoystickDriver.provisionprofile"
            driver = root / "OpenJoystickDriver_VirtualHIDDevice.provisionprofile"
            write_profile(host, "OpenJoystickDriver Development")
            write_profile(driver, "OpenJoystickDriver DriverKit Development")
            dev_env = root / ".env.dev"
            release_env = root / ".env.release"
            environment = os.environ.copy()
            environment.update(
                {
                    "PATH": f"{bin_dir}:{environment['PATH']}",
                    "PROJECT_DIR": str(root),
                    "DEV_ENV": str(dev_env),
                    "REL_ENV": str(release_env),
                    "GUI_DEV_PROFILE": str(host),
                    "GUI_DEVID_PROFILE": str(root / "missing-release.provisionprofile"),
                    "DEXT_PROFILE": str(driver),
                    "APPLE_DEV_IDENTITY": "development-identity-sha1",
                }
            )

            result = subprocess.run(
                [sys.executable, str(ROOT / "scripts/signing/configure.py")],
                cwd=ROOT,
                env=environment,
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('CODESIGN_IDENTITY="development-identity-sha1"', dev_env.read_text())
            self.assertIn('DEVELOPMENT_TEAM="ABCDEF1234"', dev_env.read_text())
            self.assertIn(
                'OJD_USE_LEGACY_DRIVERKIT_PROFILE="0"', dev_env.read_text()
            )
            self.assertIn(
                'GUI_PROVISIONING_PROFILE="$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver.provisionprofile"',
                dev_env.read_text(),
            )
            self.assertFalse(release_env.exists())
            self.assertIn("optional Developer ID profile is absent", result.stderr)

            legacy_host = plistlib.loads(host.read_bytes())
            legacy_host["Entitlements"][
                "com.apple.developer.driverkit.userclient-access"
            ] = [
                "com.openjoystickdriver.VirtualHIDDevice\n"
                "com.openjoystickdriver.daemon"
            ]
            host.write_bytes(plistlib.dumps(legacy_host))
            legacy_result = subprocess.run(
                [sys.executable, str(ROOT / "scripts/signing/configure.py")],
                cwd=ROOT,
                env=environment,
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(legacy_result.returncode, 0, legacy_result.stderr)
            self.assertIn(
                'OJD_USE_LEGACY_DRIVERKIT_PROFILE="1"', dev_env.read_text()
            )
            self.assertIn("Compatibility output", legacy_result.stderr)
            self.assertIn("relay diagnostics", legacy_result.stderr)

    def test_doctor_reports_development_ready_without_publisher_assets(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            profiles = root / "profiles"
            profiles.mkdir()
            certificate = b"test-apple-development-certificate"
            certificate_sha1 = hashlib.sha1(
                certificate, usedforsecurity=False
            ).hexdigest()
            common = {
                "TeamIdentifier": ["ABCDEF1234"],
                "DeveloperCertificates": [certificate],
            }
            host = {
                **common,
                "Name": "OpenJoystickDriver Development",
                "Entitlements": {
                    "com.apple.developer.system-extension.install": True,
                    "com.apple.developer.hid.virtual.device": True,
                    "com.apple.developer.driverkit.userclient-access": [
                        "com.openjoystickdriver.VirtualHIDDevice"
                    ],
                },
            }
            driver = {
                **common,
                "Name": "OpenJoystickDriver DriverKit Development",
                "Entitlements": {
                    "com.apple.developer.driverkit": True,
                    "com.apple.developer.driverkit.family.hid.device": True,
                    "com.apple.developer.driverkit.transport.hid": True,
                    "com.apple.developer.driverkit.family.hid.eventservice": True,
                },
            }
            (profiles / "OpenJoystickDriver.provisionprofile").write_bytes(
                plistlib.dumps(host)
            )
            (
                profiles / "OpenJoystickDriver_VirtualHIDDevice.provisionprofile"
            ).write_bytes(plistlib.dumps(driver))
            bin_dir = root / "bin"
            bin_dir.mkdir()
            fake_security = bin_dir / "security"
            fake_security.write_text(
                "#!/usr/bin/env bash\n"
                "if [[ \"$1\" == cms ]]; then cat \"${@: -1}\"; exit 0; fi\n"
                "if [[ \"$1\" == find-identity ]]; then\n"
                f"  echo '  1) {certificate_sha1} \"Apple Development: Test (ABCDEF1234)\"'\n"
                "  echo '     1 valid identities found'\n"
                "  exit 0\n"
                "fi\n"
                "exit 1\n"
            )
            fake_security.chmod(0o755)
            environment = os.environ.copy()
            environment["PATH"] = f"{bin_dir}:{environment['PATH']}"
            environment["OJD_PROFILES_DIR"] = str(profiles)
            environment["OJD_USE_LEGACY_DRIVERKIT_PROFILE"] = "0"

            result = subprocess.run(
                [sys.executable, str(ROOT / "scripts/signing/doctor.py")],
                cwd=ROOT,
                env=environment,
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Development signing: READY", result.stdout)
            self.assertIn(
                "Publisher release signing: NOT CONFIGURED", result.stdout
            )
            self.assertIn("./scripts/ojd rebuild dev", result.stdout)

    def test_doctor_accepts_known_legacy_profile_only_in_explicit_dev_mode(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            profiles = root / "profiles"
            profiles.mkdir()
            certificate = b"test-apple-development-certificate"
            certificate_sha1 = hashlib.sha1(
                certificate, usedforsecurity=False
            ).hexdigest()
            common = {
                "TeamIdentifier": ["ABCDEF1234"],
                "DeveloperCertificates": [certificate],
            }
            host = {
                **common,
                "Entitlements": {
                    "com.apple.developer.system-extension.install": True,
                    "com.apple.developer.hid.virtual.device": True,
                    "com.apple.developer.driverkit.userclient-access": [
                        "com.openjoystickdriver.VirtualHIDDevice\n"
                        "com.openjoystickdriver.daemon"
                    ],
                },
            }
            driver = {
                **common,
                "Entitlements": {
                    "com.apple.developer.driverkit": True,
                    "com.apple.developer.driverkit.family.hid.device": True,
                    "com.apple.developer.driverkit.transport.hid": True,
                    "com.apple.developer.driverkit.family.hid.eventservice": True,
                },
            }
            (profiles / "OpenJoystickDriver.provisionprofile").write_bytes(
                plistlib.dumps(host)
            )
            (
                profiles / "OpenJoystickDriver_VirtualHIDDevice.provisionprofile"
            ).write_bytes(plistlib.dumps(driver))
            bin_dir = root / "bin"
            bin_dir.mkdir()
            fake_security = bin_dir / "security"
            fake_security.write_text(
                "#!/usr/bin/env bash\n"
                "if [[ \"$1\" == cms ]]; then cat \"${@: -1}\"; exit 0; fi\n"
                "if [[ \"$1\" == find-identity ]]; then\n"
                f"  echo '  1) {certificate_sha1} \"Apple Development: Test (ABCDEF1234)\"'\n"
                "  exit 0\n"
                "fi\n"
                "exit 1\n"
            )
            fake_security.chmod(0o755)
            environment = os.environ.copy()
            environment.update(
                {
                    "PATH": f"{bin_dir}:{environment['PATH']}",
                    "OJD_PROFILES_DIR": str(profiles),
                    "OJD_USE_LEGACY_DRIVERKIT_PROFILE": "1",
                }
            )

            result = subprocess.run(
                [sys.executable, str(ROOT / "scripts/signing/doctor.py")],
                cwd=ROOT,
                env=environment,
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("READY (COMPATIBILITY OUTPUT ONLY)", result.stdout)
            self.assertIn("generated host signing omits DriverKit", result.stdout)
            self.assertIn(
                "Compatibility IOHIDUserDevice output remains available", result.stdout
            )
            self.assertIn("DriverKit relay diagnostics require", result.stdout)


if __name__ == "__main__":
    unittest.main()
