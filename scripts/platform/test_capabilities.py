from __future__ import annotations

import io
import runpy
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from capabilities import (
    Capability,
    CapabilityError,
    OutcomeKind,
    Resolver,
    requirements_for,
)


class TTYInput(io.StringIO):
    def isatty(self) -> bool:
        return True


def completed(command: list[str], returncode: int = 0) -> subprocess.CompletedProcess[str]:
    return subprocess.CompletedProcess(command, returncode, "", "")


class CapabilityResolverTests(unittest.TestCase):
    def test_swift_testing_helper_crash_is_recoverable(self) -> None:
        dispatcher = runpy.run_path(str(Path(__file__).resolve().parents[1] / "ojd"))
        crashed = dispatcher["swift_testing_helper_crashed"]
        self.assertTrue(
            crashed(
                b"error: Process '/tmp/swiftpm-testing-helper' "
                b"exited with unexpected signal code 11"
            )
        )
        self.assertFalse(crashed(b"error: Test failed"))

    def test_formula_is_available_without_repair(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            resolver = Resolver(
                Path(directory),
                environ={"PATH": "/fake"},
                which=lambda executable, _path: f"/fake/{executable}",
            )
            outcome = resolver.ensure(Capability.SWIFTLINT)
        self.assertEqual(outcome.kind, OutcomeKind.AVAILABLE)

    def test_homebrew_install_repairs_and_resumes(self) -> None:
        installed: set[str] = {"brew"}
        commands: list[list[str]] = []

        def which(executable: str, _path: str | None) -> str | None:
            return f"/fake/{executable}" if executable in installed else None

        def run(command: list[str], **_kwargs: object) -> subprocess.CompletedProcess[str]:
            commands.append(command)
            if command == ["/fake/brew", "install", "swiftlint"]:
                installed.add("swiftlint")
            return completed(command)

        with tempfile.TemporaryDirectory() as directory:
            resolver = Resolver(
                Path(directory),
                environ={"PATH": "/fake"},
                input_stream=TTYInput("yes\n"),
                output=io.StringIO(),
                which=which,
                run=run,
            )
            outcome = resolver.ensure(Capability.SWIFTLINT)
        self.assertEqual(outcome.kind, OutcomeKind.REPAIRED)
        self.assertEqual(commands, [["/fake/brew", "install", "swiftlint"]])

    def test_declined_formula_install_is_terminal(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            resolver = Resolver(
                Path(directory),
                environ={"PATH": "/fake"},
                input_stream=TTYInput("no\n"),
                output=io.StringIO(),
                which=lambda executable, _path: "/fake/brew" if executable == "brew" else None,
            )
            with self.assertRaises(CapabilityError) as context:
                resolver.resolve([Capability.SWIFTLINT])
        self.assertEqual(context.exception.outcome.kind, OutcomeKind.DECLINED)

    def test_noninteractive_mode_never_installs_formula(self) -> None:
        commands: list[list[str]] = []

        def run(command: list[str], **_kwargs: object) -> subprocess.CompletedProcess[str]:
            commands.append(command)
            return completed(command)

        with tempfile.TemporaryDirectory() as directory:
            resolver = Resolver(
                Path(directory),
                environ={"PATH": "/fake", "CI": "1"},
                input_stream=TTYInput(),
                which=lambda executable, _path: "/fake/brew" if executable == "brew" else None,
                run=run,
            )
            outcome = resolver.ensure(Capability.SWIFTLINT)
        self.assertEqual(outcome.kind, OutcomeKind.UNSUPPORTED)
        self.assertEqual(commands, [])

    def test_missing_homebrew_opens_only_official_page(self) -> None:
        commands: list[list[str]] = []

        def run(command: list[str], **_kwargs: object) -> subprocess.CompletedProcess[str]:
            commands.append(command)
            return completed(command)

        with tempfile.TemporaryDirectory() as directory:
            resolver = Resolver(
                Path(directory),
                environ={"PATH": "/fake"},
                input_stream=TTYInput(),
                which=lambda _executable, _path: None,
                run=run,
            )
            outcome = resolver.ensure(Capability.JUST)
        self.assertEqual(outcome.kind, OutcomeKind.EXTERNALLY_BLOCKED)
        self.assertEqual(commands, [["open", "https://brew.sh/"]])

    def test_offline_schema_install_leaves_no_environment(self) -> None:
        def run(command: list[str], **_kwargs: object) -> subprocess.CompletedProcess[str]:
            return completed(command, 1)

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            resolver = Resolver(root, environ={}, run=run)
            outcome = resolver.ensure(Capability.SCHEMA_PYTHON)
            self.assertFalse((root / ".build/schema-validator").exists())
            self.assertEqual(list((root / ".build").iterdir()), [])
        self.assertEqual(outcome.kind, OutcomeKind.UNSUPPORTED)

    def test_notary_configuration_is_atomic_and_preserves_signing(self) -> None:
        commands: list[list[str]] = []

        def run(command: list[str], **_kwargs: object) -> subprocess.CompletedProcess[str]:
            commands.append(command)
            return completed(command)

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            env_file = root / ".env.release"
            env_file.write_text('CODESIGN_IDENTITY="ABC"\nDEVELOPMENT_TEAM="TEAM123456"\n', encoding="utf-8")
            resolver = Resolver(
                root,
                environ={"PATH": "/fake"},
                input_stream=TTYInput("publisher@example.com\n"),
                output=io.StringIO(),
                run=run,
            )
            outcome = resolver.ensure(Capability.NOTARIZATION)
            content = env_file.read_text(encoding="utf-8")
        self.assertEqual(outcome.kind, OutcomeKind.REPAIRED)
        self.assertIn('CODESIGN_IDENTITY="ABC"', content)
        self.assertIn('NOTARIZE_KEYCHAIN_PROFILE="OpenJoystickDriver"', content)
        self.assertNotIn("password", " ".join(commands[0]).lower())

    def test_failed_notary_validation_does_not_change_environment(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            env_file = root / ".env.release"
            original = 'DEVELOPMENT_TEAM="TEAM123456"\n'
            env_file.write_text(original, encoding="utf-8")
            resolver = Resolver(
                root,
                environ={"PATH": "/fake"},
                input_stream=TTYInput("publisher@example.com\n"),
                output=io.StringIO(),
                run=lambda command, **_kwargs: completed(command, 1),
            )
            outcome = resolver.ensure(Capability.NOTARIZATION)
            self.assertEqual(env_file.read_text(encoding="utf-8"), original)
        self.assertEqual(outcome.kind, OutcomeKind.UNSUPPORTED)

    def test_packaging_declares_configuration_before_execution(self) -> None:
        requirements = requirements_for(["package", "tester"])
        self.assertEqual(
            requirements,
            (
                Capability.SWIFT_TOOLCHAIN,
                Capability.FULL_XCODE,
                Capability.RELEASE_SIGNING,
                Capability.NOTARIZATION,
            ),
        )

    def test_help_routes_never_trigger_repairs(self) -> None:
        self.assertEqual(requirements_for(["release", "package", "--help"]), ())
        self.assertEqual(requirements_for(["release", "notarize", "help"]), ())

    def test_ci_notary_secrets_need_no_keychain_repair(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            resolver = Resolver(
                Path(directory),
                environ={
                    "CI": "1",
                    "NOTARIZE_APPLE_ID": "publisher@example.com",
                    "NOTARIZE_PASSWORD": "secret",
                    "DEVELOPMENT_TEAM": "TEAM123456",
                },
                run=lambda command, **_kwargs: self.fail(f"unexpected command: {command}"),
            )
            outcome = resolver.ensure(Capability.NOTARIZATION)
        self.assertEqual(outcome.kind, OutcomeKind.AVAILABLE)

    def test_missing_xcode_opens_mac_app_store(self) -> None:
        commands: list[list[str]] = []

        def run(command: list[str], **_kwargs: object) -> subprocess.CompletedProcess[str]:
            commands.append(command)
            return completed(command)

        with tempfile.TemporaryDirectory() as directory:
            resolver = Resolver(
                Path(directory),
                environ={"OJD_APPLICATIONS_DIR": directory},
                input_stream=TTYInput(),
                run=run,
            )
            outcome = resolver.ensure(Capability.FULL_XCODE)
        self.assertEqual(outcome.kind, OutcomeKind.EXTERNALLY_BLOCKED)
        self.assertEqual(commands, [["open", "macappstore://itunes.apple.com/app/id497799835"]])

    def test_every_just_recipe_delegates_to_dispatcher(self) -> None:
        root = Path(__file__).resolve().parents[2]
        commands = [
            line.strip()
            for line in (root / "justfile").read_text(encoding="utf-8").splitlines()
            if line.startswith("    ") and not line.lstrip().startswith("#")
        ]
        self.assertEqual(commands[0], "@just --list")
        self.assertTrue(
            all(command.startswith("./scripts/ojd ") for command in commands[1:])
        )

    def test_profile_install_discovers_downloads(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            downloads = home / "Downloads"
            downloads.mkdir()
            names = (
                "OpenJoystickDriver.provisionprofile",
                "OpenJoystickDriver_XboxUSBDevice.provisionprofile",
            )
            for name in names:
                (downloads / name).write_text(name, encoding="utf-8")
            script = Path(__file__).resolve().parents[1] / "signing/signing.sh"
            result = subprocess.run(
                ["/usr/bin/env", "bash", str(script), "install-profiles"],
                env={"HOME": str(home), "PATH": "/usr/bin:/bin"},
                capture_output=True,
                text=True,
                check=False,
            )
            destination = home / "Library/MobileDevice/Provisioning Profiles"
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(all((destination / name).is_file() for name in names))

if __name__ == "__main__":
    unittest.main()
