from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import Self
from unittest.mock import patch

from Scripts.Command import dispatcher, execution

XCTEST_RUN = """\
\t Executed 5 tests, with 0 failures (0 unexpected) in 2.3 (2.3) seconds
\t Executed 16 tests, with 0 failures (0 unexpected) in 8.9 (8.9) seconds
\t Executed 16 tests, with 0 failures (0 unexpected) in 8.9 (8.9) seconds
Test run with 0 tests in 0 suites passed after 0.001 seconds.
"""
TESTING_RUN = "Test run with 4 tests in 1 suite passed after 0.1 seconds.\n"
COMPILER_WARNING = "/src/a.swift:3:5: warning: result of call to 'map' is unused\n"
LINKER_WARNING = (
    "ld: warning: building for macOS-12.0, but linking with dylib built for 13.0\n"
)
NO_TESTS_RUN = """\
\t Executed 0 tests, with 0 failures (0 unexpected) in 0.0 (0.0) seconds
Test run with 0 tests in 0 suites passed after 0.001 seconds.
"""


class TargetInvoked(Exception):
    pass


class ScriptTree:
    """A copy of the scripts whose installed app executable is a stub in a temporary directory."""

    def __init__(self, root: Path) -> None:
        self.root = root
        self.directory = tempfile.TemporaryDirectory()
        self.path = Path(self.directory.name).resolve()

    def __enter__(self) -> Self:
        shutil.copytree(
            self.root / "Scripts", self.path / "Scripts", ignore=ignore_cache
        )
        shutil.copy(self.root / ".swift-version", self.path / ".swift-version")
        info = self.path / "Sources/OpenJoystickDriver/App/Info.plist"
        info.parent.mkdir(parents=True)
        shutil.copy(self.root / "Sources/OpenJoystickDriver/App/Info.plist", info)
        self.set_cli(self.path / "bin/OpenJoystickDriver")
        return self

    def __exit__(self, *_: object) -> None:
        self.directory.cleanup()

    def set_cli(self, cli: Path) -> None:
        environment = self.path / "Scripts/Platform/environment.sh"
        lines = environment.read_text().splitlines()
        lines = [
            f'OJD_APP_CLI="{cli}"' if line.startswith("OJD_APP_CLI=") else line
            for line in lines
        ]
        environment.write_text("\n".join(lines) + "\n")

    def stub(self, path: Path, body: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(f"#!/usr/bin/env bash\n{body}\n")
        path.chmod(0o755)

    def write_stubs(self, dext_status: int) -> None:
        self.stub(self.path / "bin/OpenJoystickDriver", "exit 0")
        self.stub(self.path / "stubs/xmake", "exit 0")
        self.stub(
            self.path / "Scripts/Diagnostics/dext/diagnose.sh", f"exit {dext_status}"
        )
        self.stub(
            self.path / ".build/debug/OpenJoystickDriverGameControllerProbe", "exit 0"
        )
        (self.path / "Tools/SDLGamepadProbe").mkdir(parents=True)
        (self.path / "Tools/SDLGamepadProbe/xmake.lua").write_text("")

    def run(self, script: str, *arguments: str) -> subprocess.CompletedProcess[str]:
        environment = {**os.environ, "PATH": f"{self.path}/stubs:{os.environ['PATH']}"}
        return subprocess.run(
            ["/bin/bash", str(self.path / "Scripts" / script), *arguments],
            cwd=self.path,
            env=environment,
            capture_output=True,
            text=True,
            check=False,
            timeout=120,
        )


def ignore_cache(_: str, names: list[str]) -> list[str]:
    return [name for name in names if name == "__pycache__"]


class DispatcherTests(unittest.TestCase):
    root = Path(__file__).resolve().parents[2]
    command = root / "Scripts/ojd"

    def run_ojd(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(self.command), *arguments],
            cwd=self.root,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_help_route_succeeds(self) -> None:
        self.assertEqual(self.run_ojd("--help").returncode, 0)

    def test_help_flags_and_help_word_succeed_on_stdout(self) -> None:
        for argument in ("-h", "--help", "help"):
            with self.subTest(argument=argument):
                result = self.run_ojd(argument)
                self.assertEqual(result.returncode, 0)
                self.assertTrue(result.stdout.strip())
                self.assertEqual(result.stderr, "")

    def test_version_reports_the_app_version(self) -> None:
        result = self.run_ojd("--version")
        self.assertEqual(result.returncode, 0)
        self.assertIn(dispatcher.project_version(), result.stdout)

    def test_errors_use_lowercase_prefix_on_stderr(self) -> None:
        for arguments in (("unknown",), ("build", "nuke"), ("--bogus",)):
            with self.subTest(arguments=arguments):
                result = self.run_ojd(*arguments)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, "")
                self.assertIn("error:", result.stderr)
                self.assertNotIn("ERROR:", result.stderr)

    def test_build_help_lists_every_build_route(self) -> None:
        result = self.run_ojd("build", "help")
        self.assertEqual(result.returncode, 0)
        for route in (
            "build dev",
            "build release",
            "build dext",
            "build install dev|release",
            "build install-fast dev",
        ):
            with self.subTest(route=route):
                self.assertIn(f"./Scripts/ojd {route}\n", result.stdout)

    def test_build_routes_forward_arguments(self) -> None:
        routes = (
            (
                ("build", "dev"),
                "Build/build.sh",
                ["build", "dev"],
                None,
            ),
            (
                ("build", "release"),
                "Build/build.sh",
                ["build", "release"],
                {"OJD_ENV": "release"},
            ),
            (
                ("build", "dext"),
                "Build/build.sh",
                ["build", "dext"],
                None,
            ),
            (
                ("build", "install", "dev"),
                "Build/install.sh",
                ["install", "dev"],
                None,
            ),
            (
                ("build", "install", "release"),
                "Build/install.sh",
                ["install", "release"],
                {"OJD_ENV": "release"},
            ),
            (
                ("build", "install-fast", "dev"),
                "Build/install.sh",
                ["install-fast", "dev"],
                None,
            ),
        )
        for arguments, target, forwarded_arguments, environment in routes:
            with self.subTest(arguments=arguments):
                with (
                    patch.object(
                        dispatcher,
                        "exec_target",
                        side_effect=TargetInvoked,
                    ) as execute,
                    self.assertRaises(TargetInvoked),
                ):
                    dispatcher.dispatch(list(arguments))
                execute.assert_called_once_with(
                    target,
                    forwarded_arguments,
                    env=environment,
                )

    def test_snapshots_routes_forward_to_the_comparison_script(self) -> None:
        for argument in ("check", "write"):
            with self.subTest(argument=argument):
                with (
                    patch.object(
                        dispatcher,
                        "exec_target",
                        side_effect=TargetInvoked,
                    ) as execute,
                    self.assertRaises(TargetInvoked),
                ):
                    dispatcher.dispatch(["snapshots", argument])
                execute.assert_called_once_with(
                    "Quality/equivalence_snapshots.py",
                    [argument],
                    python=True,
                )

    def test_sdl_probe_routes_forward_to_the_backend_script(self) -> None:
        for route in ("sdl3", "sdl3-gamecontroller", "sdl3-hidapi-x360"):
            with self.subTest(route=route):
                with (
                    patch.object(
                        dispatcher,
                        "exec_target",
                        side_effect=TargetInvoked,
                    ) as execute,
                    self.assertRaises(TargetInvoked),
                ):
                    dispatcher.dispatch(["diagnose", route, "--seconds", "3"])
                execute.assert_called_once_with(
                    "Diagnostics/backend.sh", [route, "--seconds", "3"]
                )

    def test_browsers_route_forwards_to_the_browser_harness(self) -> None:
        with (
            patch.object(
                dispatcher, "exec_target", side_effect=TargetInvoked
            ) as execute,
            self.assertRaises(TargetInvoked),
        ):
            dispatcher.dispatch(["diagnose", "browsers", "--browsers", "safari"])
        execute.assert_called_once_with(
            "Diagnostics/browser_gamepad.py", ["--browsers", "safari"], python=True
        )

    def test_backend_script_takes_the_gamecontroller_hints_from_virtual_launch(
        self,
    ) -> None:
        script = (self.root / "Scripts/Diagnostics/backend.sh").read_text()
        self.assertIn("virtual launch --sdl-gamecontroller-backend --", script)
        self.assertNotIn("SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS", script)
        gamecontroller = script.split("run_sdl3_gamecontroller_probe() {")[1].split(
            "run_sdl3_hidapi_x360_probe() {"
        )[0]
        self.assertNotIn("SDL_JOYSTICK_", gamecontroller)

    def test_backend_script_has_one_cli_path_and_no_hidden_reset(self) -> None:
        script = (self.root / "Scripts/Diagnostics/backend.sh").read_text()
        self.assertNotIn("/Applications/OpenJoystickDriver.app", script)
        self.assertIn("require_ojd_app_cli", script)
        for text in ("OJD_CLI", "CLI_BIN", "virtual reset"):
            self.assertNotIn(text, script)

    def test_app_cli_path_is_defined_only_in_the_environment_script(self) -> None:
        path = "/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver"
        owners = [
            script.relative_to(self.root).as_posix()
            for script in sorted((self.root / "Scripts").rglob("*"))
            if script.is_file()
            and script.suffix in {".sh", ""}
            and path in script.read_text(errors="ignore")
        ]
        self.assertEqual(owners, ["Scripts/Platform/environment.sh"])

    def test_rumble_motors_fails_when_the_installed_cli_is_missing(self) -> None:
        with ScriptTree(self.root) as tree:
            tree.set_cli(tree.path / "missing/OpenJoystickDriver")
            completed = tree.run("Diagnostics/rumble-motors.sh", "0x045E", "0x028E")
        self.assertEqual(completed.returncode, 2)
        self.assertIn(
            f"OpenJoystickDriver is not installed at {tree.path}/missing/OpenJoystickDriver",
            completed.stderr,
        )
        self.assertNotIn("Testing", completed.stdout)

    def test_backends_reports_each_step_and_fails_when_a_step_failed(self) -> None:
        with ScriptTree(self.root) as tree:
            tree.write_stubs(dext_status=3)
            completed = tree.run("Diagnostics/backend.sh", "backends", "--seconds", "1")
        self.assertEqual(completed.returncode, 1)
        self.assertEqual(completed.stdout.count("Step exit status:"), 4)
        self.assertIn(
            "3) DriverKit backend diagnostics:\nStep exit status: 3", completed.stdout
        )
        self.assertEqual(completed.stdout.count("Step exit status: 0"), 3)
        self.assertIn("1 backend step(s) failed.", completed.stdout)

    def test_backends_exits_zero_when_every_step_passed(self) -> None:
        with ScriptTree(self.root) as tree:
            tree.write_stubs(dext_status=0)
            completed = tree.run("Diagnostics/backend.sh", "backends", "--seconds", "1")
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        self.assertEqual(completed.stdout.count("Step exit status: 0"), 4)

    def test_unknown_route_fails_with_usage_status(self) -> None:
        self.assertEqual(self.run_ojd("unknown").returncode, 2)

    def test_unknown_subroutes_fail_with_usage_status(self) -> None:
        for arguments in (
            ("build", "notaroute"),
            ("check", "notaroute"),
            ("test", "notaroute"),
            ("notaroute", "check"),
        ):
            with self.subTest(arguments=arguments):
                self.assertEqual(self.run_ojd(*arguments).returncode, 2)

    def test_check_tools_runs_xmake_with_the_environment(self) -> None:
        completed = subprocess.CompletedProcess(
            args=[], returncode=0, stdout=XCTEST_RUN
        )
        with patch.object(
            dispatcher.subprocess, "run", return_value=completed
        ) as run_command:
            self.assertEqual(dispatcher.dispatch(["check", "tools"]), 0)
        command = run_command.call_args_list[0].args[0]
        self.assertEqual(command[:2], ["/bin/bash", "-c"])
        self.assertIn('source "$1"', command[2])
        self.assertIn("exec xmake build", command[2])
        self.assertEqual(
            command[4:],
            [
                str(dispatcher.ENVIRONMENT),
                str(dispatcher.PROJECT_DIR / "Tools/SDLGamepadProbe"),
            ],
        )

    def test_check_tools_runs_the_bridge_package_tests(self) -> None:
        completed = subprocess.CompletedProcess(
            args=[], returncode=0, stdout=XCTEST_RUN
        )
        with patch.object(
            dispatcher.subprocess, "run", return_value=completed
        ) as run_command:
            dispatcher.dispatch(["check", "tools"])
        self.assertEqual(run_command.call_count, 2)
        call = run_command.call_args_list[1]
        self.assertEqual(
            call.kwargs["cwd"], dispatcher.PROJECT_DIR / "Tools/WebRTCBridge"
        )
        command = call.args[0]
        self.assertIn("exec swift ", command[2])
        self.assertEqual(command[5:], ["test"])

    def test_check_tools_fails_when_the_bridge_tests_fail(self) -> None:
        results = [
            subprocess.CompletedProcess(args=[], returncode=0),
            subprocess.CompletedProcess(args=[], returncode=1, stdout=XCTEST_RUN),
        ]
        with patch.object(dispatcher.subprocess, "run", side_effect=results):
            self.assertEqual(dispatcher.dispatch(["check", "tools"]), 1)

    def test_check_tools_fails_when_the_bridge_package_executes_no_tests(self) -> None:
        results = [
            subprocess.CompletedProcess(args=[], returncode=0),
            subprocess.CompletedProcess(args=[], returncode=0, stdout=NO_TESTS_RUN),
        ]
        with patch.object(dispatcher.subprocess, "run", side_effect=results):
            self.assertEqual(dispatcher.dispatch(["check", "tools"]), 1)

    def test_check_tools_passes_on_swift_testing_alone(self) -> None:
        results = [
            subprocess.CompletedProcess(args=[], returncode=0),
            subprocess.CompletedProcess(args=[], returncode=0, stdout=TESTING_RUN),
        ]
        with patch.object(dispatcher.subprocess, "run", side_effect=results):
            self.assertEqual(dispatcher.dispatch(["check", "tools"]), 0)

    def test_check_tools_fails_when_the_probe_build_warns(self) -> None:
        results = [
            subprocess.CompletedProcess(args=[], returncode=0, stdout=COMPILER_WARNING),
            subprocess.CompletedProcess(args=[], returncode=0, stdout=XCTEST_RUN),
        ]
        with patch.object(dispatcher.subprocess, "run", side_effect=results):
            self.assertEqual(dispatcher.dispatch(["check", "tools"]), 1)

    def test_check_tools_fails_when_the_bridge_build_warns(self) -> None:
        results = [
            subprocess.CompletedProcess(args=[], returncode=0),
            subprocess.CompletedProcess(
                args=[], returncode=0, stdout=LINKER_WARNING + XCTEST_RUN
            ),
        ]
        with patch.object(dispatcher.subprocess, "run", side_effect=results):
            self.assertEqual(dispatcher.dispatch(["check", "tools"]), 1)

    def test_check_swift_builds_then_tests_without_building_again(self) -> None:
        completed = subprocess.CompletedProcess(args=[], returncode=0, stdout="")
        with patch.object(
            dispatcher.subprocess, "run", return_value=completed
        ) as run_command:
            self.assertEqual(dispatcher.dispatch(["check", "swift"]), 0)
        commands = [call.args[0][5:] for call in run_command.call_args_list]
        self.assertEqual(
            commands,
            [
                ["build", "--build-tests"],
                ["test", "--skip-build", "--no-parallel"],
            ],
        )
        for call in run_command.call_args_list:
            self.assertEqual(call.kwargs["cwd"], dispatcher.PROJECT_DIR)

    def test_check_swift_fails_on_a_build_warning_and_runs_no_tests(self) -> None:
        completed = subprocess.CompletedProcess(
            args=[], returncode=0, stdout=COMPILER_WARNING
        )
        with patch.object(
            dispatcher.subprocess, "run", return_value=completed
        ) as run_command:
            self.assertEqual(dispatcher.dispatch(["check", "swift"]), 1)
        self.assertEqual(run_command.call_count, 1)

    def test_warning_lines_finds_compiler_linker_and_package_warnings(self) -> None:
        output = (
            COMPILER_WARNING
            + LINKER_WARNING
            + "warning: 'pkg': found 1 file(s) which are unhandled\n"
            + "\x1b[1;33mwarning: \x1b[1;39mcolored\x1b[0;0m\n"
            + "Build complete! 0 warnings\n"
            + "swiftc -warnings-as-errors -c main.swift\n"
        )
        self.assertEqual(len(execution.warning_lines(output)), 4)

    def test_executed_test_count_adds_xctest_and_swift_testing(self) -> None:
        count = execution.executed_test_count
        self.assertEqual(count(XCTEST_RUN), 16)
        self.assertEqual(count(TESTING_RUN), 4)
        self.assertEqual(count(XCTEST_RUN + TESTING_RUN), 20)
        self.assertEqual(count(NO_TESTS_RUN), 0)
        self.assertEqual(count(""), 0)

    def test_hooks_install_points_hooks_path_at_the_main_checkout(self) -> None:
        completed = subprocess.CompletedProcess([], 0)
        with (
            patch(
                "Scripts.Command.execution.main_checkout_dir",
                return_value=Path("/main"),
            ),
            patch(
                "Scripts.Command.execution.subprocess.run", return_value=completed
            ) as run,
        ):
            self.assertEqual(dispatcher.dispatch(["hooks", "install"]), 0)
        self.assertEqual(
            run.call_args.args[0],
            ["git", "config", "core.hooksPath", "/main/.githooks"],
        )

    def test_hooks_validate_checks_hooks_path_and_hook_files(self) -> None:
        main = "<main>/.githooks"
        for configured, files, expected in (
            (main, ("pre-push",), 0),
            (".githooks", ("pre-push",), 1),
            ("", ("pre-push",), 1),
            ("other/hooks", ("pre-push",), 1),
            (main, (), 1),
        ):
            with (
                self.subTest(configured=configured, files=files),
                tempfile.TemporaryDirectory() as directory,
            ):
                root = Path(directory)
                (root / ".githooks").mkdir()
                for name in files:
                    (root / ".githooks" / name).write_text("")
                value = configured.replace("<main>", str(root))
                completed = subprocess.CompletedProcess([], 0, value + "\n", "")
                with (
                    patch("Scripts.Command.execution.PROJECT_DIR", root),
                    patch(
                        "Scripts.Command.execution.main_checkout_dir",
                        return_value=root,
                    ),
                    patch(
                        "Scripts.Command.execution.subprocess.run",
                        return_value=completed,
                    ),
                ):
                    self.assertEqual(
                        dispatcher.dispatch(["hooks", "validate"]), expected
                    )
