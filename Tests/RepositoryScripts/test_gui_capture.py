from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from collections.abc import Callable
from datetime import datetime
from pathlib import Path
from unittest.mock import patch

from Scripts.Command import dispatcher
from Scripts.GUI import capture


class TargetInvoked(Exception):
    pass


UNLOCKED = "locked=false console=true"
APP_WINDOW: dict[str, object] = {
    "id": 9,
    "pid": 1,
    "owner": "OpenJoystickDriver",
    "layer": 0,
    "alpha": 1,
    "x": 10,
    "y": 20,
    "width": 300,
    "height": 200,
}


class GuiCaptureTests(unittest.TestCase):
    def test_dispatcher_routes_shots_capture(self) -> None:
        with (
            patch.object(
                dispatcher, "exec_target", side_effect=TargetInvoked
            ) as execute,
            self.assertRaises(TargetInvoked),
        ):
            dispatcher.dispatch(["shots", "capture", "--all"])
        execute.assert_called_once_with("GUI/capture.py", ["--all"], python=True)

    def test_dispatcher_rejects_unknown_shots_command(self) -> None:
        with self.assertRaises(SystemExit):
            dispatcher.dispatch(["shots", "list"])

    def test_dispatcher_names_missing_shots_command(self) -> None:
        with (
            patch.object(dispatcher, "die", side_effect=TargetInvoked) as die,
            self.assertRaises(TargetInvoked),
        ):
            dispatcher.dispatch(["shots"])
        die.assert_called_once_with("Unknown: shots (expected: capture)")

    def test_area_and_pane_are_exclusive_choices(self) -> None:
        self.assertEqual(capture.parse_args(["--area", "Library"]).area, "Library")
        self.assertEqual(
            capture.parse_args(["--settings-pane", "Advanced"]).settings_pane,
            "Advanced",
        )
        self.assertTrue(capture.parse_args(["--all"]).all)
        for argv in (
            [],
            ["--area", "Library", "--all"],
            ["--area", "Nowhere"],
            ["--settings-pane", "Library"],
        ):
            with self.subTest(argv=argv), self.assertRaises(SystemExit):
                capture.parse_args(argv)

    def test_missing_app_is_reported(self) -> None:
        with (
            patch.object(capture, "APP", capture.PROJECT_DIR / "absent.app"),
            self.assertRaises(capture.CaptureError),
        ):
            capture.process_id()

    def process_id_with(self, completed: subprocess.CompletedProcess[str]) -> int:
        with (
            patch.object(capture, "APP", capture.PROJECT_DIR),
            patch.object(capture.subprocess, "run", return_value=completed),
        ):
            return capture.process_id()

    def test_process_id_is_the_one_running_app(self) -> None:
        self.assertEqual(self.process_id_with(self.completed(0, "412\n")), 412)

    def test_app_that_is_not_running_is_refused_by_name(self) -> None:
        with self.assertRaisesRegex(
            capture.CaptureError, "OpenJoystickDriver is not running: open "
        ):
            self.process_id_with(self.completed(1, ""))

    def test_pgrep_failure_is_not_taken_for_an_app_that_is_not_running(self) -> None:
        failed = subprocess.CompletedProcess([], 3, "", "pgrep: bad option")
        with self.assertRaisesRegex(capture.CaptureError, "exit status 3: pgrep"):
            self.process_id_with(failed)

    def test_two_running_apps_are_refused_with_their_pids(self) -> None:
        with self.assertRaisesRegex(
            capture.CaptureError, "2 OpenJoystickDriver.*412, 413"
        ):
            self.process_id_with(self.completed(0, "412\n413\n"))

    def window(self, **fields: object) -> dict:
        return {**APP_WINDOW, **fields}

    def find_window_with(self, bounds: str, windows: list[dict]) -> dict:
        with patch.object(capture, "gui", return_value=bounds):
            return capture.find_window(1, "settings", windows)

    def test_find_window_matches_bounds_within_tolerance(self) -> None:
        windows = [self.window(id=7, x=0, y=0, width=100, height=50), self.window()]
        self.assertEqual(self.find_window_with("10 20 300 200", windows)["id"], 9)
        self.assertEqual(self.find_window_with("11.5 18.5 301 199", windows)["id"], 9)

    def test_find_window_takes_only_app_windows_of_layer_zero(self) -> None:
        for other in (self.window(pid=2), self.window(layer=101)):
            with self.subTest(other=other), self.assertRaises(capture.CaptureError):
                self.find_window_with("10 20 300 200", [other])

    def test_find_window_rejects_bounds_outside_tolerance(self) -> None:
        with self.assertRaises(capture.CaptureError):
            self.find_window_with("13 20 300 200", [self.window()])
        with self.assertRaises(capture.CaptureError):
            self.find_window_with("10 20 300 200", [])

    def test_find_window_rejects_unparsable_bounds(self) -> None:
        with self.assertRaises(capture.CaptureError):
            self.find_window_with("not numbers", [])

    def test_find_window_rejects_wrong_number_of_bounds(self) -> None:
        for reported in ("1 2 3", "1 2 3 4 5", ""):
            with (
                self.subTest(reported=reported),
                self.assertRaises(capture.CaptureError),
            ):
                self.find_window_with(reported, [])

    def test_covering_windows_are_the_overlapping_ones_in_front(self) -> None:
        target = self.window()
        windows = [
            self.window(id=1, pid=5, owner="Menubar", layer=24, y=0, height=33),
            self.window(id=2, pid=6, owner="Dock", layer=20, x=0, y=0, width=1728),
            self.window(id=3, pid=7, owner="Code", x=200, y=100),
            self.window(id=4, pid=8, owner="Safari", x=310, y=20),
            target,
            self.window(id=5, pid=9, owner="Finder", x=0, y=0, width=1728),
        ]
        # Code overlaps in front; Safari only touches the right edge; the menu bar and the
        # Dock lie over every window; Finder is behind.
        self.assertEqual(capture.covering_windows(target, windows), ["Code"])
        self.assertEqual(capture.covering_windows(target, [target]), [])

    def test_the_pointer_does_not_cover_a_window(self) -> None:
        # screencapture leaves the pointer out of the image unless it is given -C.
        target = self.window()
        pointer = self.window(
            id=6, pid=10, owner="Window Server", layer=2147483630, width=28, height=40
        )
        self.assertEqual(capture.covering_windows(target, [pointer, target]), [])

    def fake_time(self) -> tuple[Callable[[], float], Callable[[float], None]]:
        now = [0.0]

        def sleep(seconds: float) -> None:
            now[0] += seconds

        return lambda: now[0], sleep

    def shoot_with(self, windows: list[dict]) -> tuple[list[list[str]], Path]:
        commands: list[list[str]] = []

        def fake_run(command: list[str]) -> str:
            commands.append(command)
            if command[0] == "osascript":
                return json.dumps(windows)
            Path(command[-1]).write_bytes(b"png")
            return ""

        folder = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, folder)
        clock, sleep = self.fake_time()
        with (
            patch.object(capture, "run", side_effect=fake_run),
            patch.object(capture, "gui", return_value="10 20 300 200"),
            patch("builtins.print"),
        ):
            capture.shoot(1, "main", folder / "main.png", 1.0, clock, sleep)
        return commands, folder

    def test_shoot_captures_the_screen_rectangle_of_the_window(self) -> None:
        # screencapture -l draws the window alone over transparency, so translucent
        # materials lose their backdrop; -R captures the screen as it shows.
        commands, folder = self.shoot_with([self.window(x=10.5)])
        self.assertEqual(
            commands[-1],
            ["screencapture", "-x", "-R", "10.5,20,300,200", str(folder / "main.png")],
        )
        captures = [command for command in commands if command[0] == "screencapture"]
        self.assertEqual(len(captures), 1)
        self.assertNotIn("-l", captures[0])

    def test_shoot_refuses_a_covered_window_and_names_the_owner(self) -> None:
        windows = [self.window(id=3, pid=7, owner="Code", x=200), self.window()]
        with self.assertRaises(capture.CaptureError) as raised:
            self.shoot_with(windows)
        self.assertIn("covered by windows of Code", str(raised.exception))
        self.assertIn(
            "after 1 s of bringing the app forward (--front-timeout)",
            str(raised.exception),
        )

    def test_capture_folders_are_unique_within_one_second(self) -> None:
        with (
            tempfile.TemporaryDirectory() as root,
            patch.object(capture, "PROJECT_DIR", Path(root)),
            patch.object(capture, "datetime") as clock,
        ):
            clock.now.return_value = datetime(2026, 1, 2, 3, 4, 5)
            names = [capture.make_folder().name for _ in range(3)]
        self.assertEqual(
            names, ["20260102-030405", "20260102-030405-1", "20260102-030405-2"]
        )

    def run_capture(
        self,
        state: tuple[bool, str | None],
        failures: dict[str, Exception],
        argv: list[str],
    ) -> tuple[int | None, list[tuple[str, ...]], Exception | None]:
        calls: list[tuple[str, ...]] = []

        def fake_gui(*command: str) -> str:
            calls.append(command)
            if command[0] in failures:
                raise failures[command[0]]
            return "Activity" if command[0] == "current-sidebar" else ""

        with (
            tempfile.TemporaryDirectory() as root,
            patch.object(capture, "PROJECT_DIR", Path(root)),
            patch.object(capture, "process_id", return_value=1),
            patch.object(capture, "require_unlocked_console_session"),
            patch.object(capture, "require_accessibility"),
            patch.object(capture, "require_english_ui"),
            patch.object(capture, "run"),
            patch.object(capture, "read_state", return_value=state),
            patch.object(capture, "gui", side_effect=fake_gui),
            patch.object(capture, "shoot"),
            patch.object(capture.sys, "stderr"),
        ):
            try:
                code = capture.capture(capture.parse_args(argv))
            except capture.CaptureError as error:
                return None, calls, error
            return code, calls, None

    def test_restore_closes_what_the_run_opened(self) -> None:
        code, calls, error = self.run_capture(
            (False, None), {}, ["--settings-pane", "Advanced"]
        )
        self.assertEqual((code, error), (0, None))
        self.assertEqual(
            calls[-3:],
            [
                ("select-sidebar", "Activity"),
                ("close-window", "settings"),
                ("close-window", "main"),
            ],
        )

    def test_restore_keeps_windows_and_tab_that_were_open(self) -> None:
        code, calls, error = self.run_capture(
            (True, "General"), {}, ["--settings-pane", "Advanced"]
        )
        self.assertEqual((code, error), (0, None))
        self.assertEqual(
            calls[-2:],
            [
                ("select-sidebar", "Activity"),
                ("open-settings", "General"),
            ],
        )
        self.assertNotIn(("close-window", "main"), calls)

    def test_failed_capture_keeps_its_error_and_still_restores(self) -> None:
        failures: dict[str, Exception] = {
            "open-settings": capture.CaptureError("menu failed"),
            "close-window": capture.CaptureError("no window"),
        }
        code, calls, error = self.run_capture(
            (False, None), failures, ["--settings-pane", "General"]
        )
        self.assertIsNone(code)
        self.assertEqual(str(error), "menu failed")
        self.assertEqual(calls[-3][0], "select-sidebar")
        self.assertEqual(calls[-1], ("close-window", "main"))

    def test_failed_restore_step_does_not_skip_later_steps(self) -> None:
        failures: dict[str, Exception] = {
            "select-sidebar": capture.CaptureError("row missing")
        }
        code, calls, error = self.run_capture(
            (False, None), failures, ["--settings-pane", "General"]
        )
        self.assertEqual((code, error), (2, None))
        self.assertEqual(calls[-1], ("close-window", "main"))

    def completed(self, code: int, out: str) -> subprocess.CompletedProcess[str]:
        return subprocess.CompletedProcess([], code, out, "")

    def probe_message(self, code: str) -> str | None:
        with patch.object(capture, "ax", return_value=code) as probe:
            try:
                capture.require_accessibility(7)
            except capture.CaptureError as error:
                message = str(error)
            else:
                message = None
        probe.assert_called_once_with("probe", 7)
        return message

    def test_accessibility_probe_granted_lets_capture_continue(self) -> None:
        self.assertIsNone(self.probe_message("0"))

    def test_accessibility_probe_untrusted_names_the_permission(self) -> None:
        message = self.probe_message("-25211")
        assert message is not None
        self.assertIn("Accessibility is not granted to the host app", message)
        self.assertIn("-25211", message)
        self.assertIn("Privacy & Security > Accessibility", message)

    def test_run_names_the_host_app_for_an_untrusted_ax_error(self) -> None:
        failure = subprocess.CompletedProcess(
            [], 1, "", "execution error: AXError -25211"
        )
        with (
            patch.object(subprocess, "run", return_value=failure),
            self.assertRaises(capture.CaptureError) as raised,
        ):
            capture.run(["osascript", "-l", "JavaScript"])
        self.assertEqual(str(raised.exception), capture.not_trusted_message("-25211"))

    def test_run_does_not_blame_permission_for_the_word_assistive(self) -> None:
        failure = subprocess.CompletedProcess([], 1, "", "assistive access failed")
        with (
            patch.object(subprocess, "run", return_value=failure),
            self.assertRaises(capture.CaptureError) as raised,
        ):
            capture.run(["osascript", "-l", "JavaScript"])
        self.assertNotIn("not granted", str(raised.exception))

    def test_accessibility_probe_other_failure_does_not_ask_for_permission(
        self,
    ) -> None:
        message = self.probe_message("-25202")
        assert message is not None
        self.assertIn("Accessibility call to OpenJoystickDriver failed", message)
        self.assertIn("-25202", message)
        self.assertIn("although the host app is trusted", message)
        self.assertNotIn("Privacy & Security", message)

    def wait_for_app(
        self, codes: list[str], timeout: float = 5.0
    ) -> tuple[str | None, int, list[float]]:
        now = [0.0]
        sleeps: list[float] = []

        def sleep(seconds: float) -> None:
            sleeps.append(seconds)
            now[0] += seconds

        with patch.object(capture, "ax", side_effect=codes) as probe:
            try:
                capture.require_accessibility(7, timeout, lambda: now[0], sleep)
            except capture.CaptureError as error:
                return str(error), probe.call_count, sleeps
        return None, probe.call_count, sleeps

    def test_app_ready_immediately_does_not_wait(self) -> None:
        self.assertEqual(self.wait_for_app(["0"]), (None, 1, []))

    def test_app_ready_after_cannot_complete_probes_waits_then_continues(self) -> None:
        message, probes, sleeps = self.wait_for_app(["-25204", "-25204", "0"])
        self.assertEqual((message, probes), (None, 3))
        self.assertEqual(sleeps, [capture.APP_READY_POLL_SECONDS] * 2)

    def test_app_not_ready_by_the_deadline_names_app_wait_timeout_and_error(
        self,
    ) -> None:
        message, probes, _ = self.wait_for_app(["-25204"] * 100, timeout=1.0)
        assert message is not None
        self.assertIn("OpenJoystickDriver did not answer Accessibility", message)
        self.assertIn("within 1 s", message)
        self.assertIn("last AXError -25204", message)
        self.assertIn("--ready-timeout", message)
        self.assertEqual(probes, 5)

    def test_other_probe_errors_are_not_waited_on(self) -> None:
        message, probes, sleeps = self.wait_for_app(["-25202"])
        assert message is not None
        self.assertEqual((probes, sleeps), (1, []))

    def test_ready_timeout_option_is_positive(self) -> None:
        self.assertEqual(
            capture.parse_args(["--all", "--ready-timeout", "3"]).ready_timeout, 3.0
        )
        self.assertEqual(
            capture.parse_args(["--all"]).ready_timeout,
            capture.APP_READY_TIMEOUT_SECONDS,
        )
        for value in ("0", "-1", "nan", "inf"):
            with self.subTest(value=value), self.assertRaises(SystemExit):
                capture.parse_args(["--all", "--ready-timeout", value])

    def test_untrusted_after_cannot_complete_stops_the_wait(self) -> None:
        message, probes, sleeps = self.wait_for_app(["-25204", "-25211"])
        assert message is not None
        self.assertIn("Accessibility is not granted to the host app", message)
        self.assertEqual((probes, len(sleeps)), (2, 1))

    def test_last_sleep_does_not_pass_the_deadline(self) -> None:
        _, _, sleeps = self.wait_for_app(["-25204"] * 100, timeout=0.6)
        self.assertEqual(len(sleeps), 3)
        self.assertAlmostEqual(sum(sleeps), 0.6)

    def test_capture_passes_the_ready_timeout_to_the_wait(self) -> None:
        with (
            patch.object(capture, "process_id", return_value=7),
            patch.object(capture, "session_state", return_value=UNLOCKED),
            patch.object(
                capture, "require_accessibility", side_effect=TargetInvoked
            ) as wait,
            self.assertRaises(TargetInvoked),
        ):
            capture.capture(
                capture.parse_args(["--area", "Controllers", "--ready-timeout", "4"])
            )
        wait.assert_called_once_with(7, 4.0)

    @unittest.skipUnless(
        shutil.which("osascript"), "osascript is not installed: ax.js needs JXA"
    )
    def test_ax_error_codes_are_classified(self) -> None:
        harness = (
            "ObjC.import('Foundation');"
            f"const path = {json.dumps(str(capture.GUI_DIR / 'ax.js'))};"
            "const source = $.NSString.stringWithContentsOfFileEncodingError("
            "path, $.NSUTF8StringEncoding, null).js;"
            "const classify = new Function(source + '; return classifyAxCode;')();"
            "JSON.stringify([0, -25205, -25212, -25204, -25202, -25211, -25201]"
            ".map(classify))"
        )
        result = subprocess.run(
            ["osascript", "-l", "JavaScript", "-e", harness],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            json.loads(result.stdout),
            ["ok", "absent", "absent", "transient", "transient", "error", "error"],
        )

    @unittest.skipUnless(
        shutil.which("osascript"), "osascript is not installed: ax.js needs JXA"
    )
    def test_wait_for_handles_transient_and_fatal_errors(self) -> None:
        harness = (
            "ObjC.import('Foundation');"
            f"const path = {json.dumps(str(capture.GUI_DIR / 'ax.js'))};"
            "const source = $.NSString.stringWithContentsOfFileEncodingError("
            "path, $.NSUTF8StringEncoding, null).js;"
            "const waitFor = new Function('delay', source + '; return waitFor;')("
            "() => {});"
            "const failing = (code) => { const e = new Error('read failed');"
            " e.axCode = code; return e; };"
            "const outcome = (condition) => { try {"
            " return 'value ' + waitFor(condition, 'thing did not appear');"
            " } catch (e) { return 'error ' + e.message; } };"
            "let calls = 0;"
            "const recovers = outcome(() => { if (calls++ === 0) throw failing(-25204);"
            " return 'ready'; });"
            "let fatalCalls = 0;"
            "const fatal = outcome(() => { fatalCalls++; throw failing(-25211); });"
            "const never = outcome(() => { throw failing(-25204); });"
            "JSON.stringify({recovers, fatal, fatalCalls, never})"
        )
        result = subprocess.run(
            ["osascript", "-l", "JavaScript", "-e", harness],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        reported = json.loads(result.stdout)
        self.assertEqual(reported["recovers"], "value ready")
        self.assertEqual(reported["fatal"], "error read failed")
        self.assertEqual(reported["fatalCalls"], 1)
        self.assertIn("thing did not appear", reported["never"])
        self.assertIn("last AXError -25204", reported["never"])

    @unittest.skipUnless(
        shutil.which("osascript"), "osascript is not installed: ax.js needs JXA"
    )
    def test_only_the_status_item_press_accepts_a_tracking_menu(self) -> None:
        # A fake `$` records the timeouts and answers AXPress with the given code; every
        # other name goes to the bridge.
        harness = (
            "ObjC.import('Foundation');"
            f"const path = {json.dumps(str(capture.GUI_DIR / 'ax.js'))};"
            "const source = $.NSString.stringWithContentsOfFileEncodingError("
            "path, $.NSUTF8StringEncoding, null).js;"
            "const calls = []; let pressCode = 0;"
            "const fake = { AXUIElementSetMessagingTimeout: (element, seconds) => {"
            " calls.push('timeout ' + seconds); return 0; },"
            " AXUIElementPerformAction: (element, action) => {"
            " calls.push(action); return pressCode; },"
            " AXUIElementCopyAttributeValue: () => -25205 };"
            "const bridged = $;"
            "const proxy = new Proxy({}, { get: (target, name) =>"
            " name in fake ? fake[name] : bridged[name] });"
            "const [pressStatusItem, pressMenuElement] = new Function('$', source +"
            " '; return [pressStatusItem, pressMenuElement];')(proxy);"
            "const outcome = (press, code) => { calls.length = 0; pressCode = code;"
            " try { press('item', 'menu.file'); return calls.join(', '); }"
            " catch (e) { return calls.join(', ') + ' -> ' + e.message; } };"
            "JSON.stringify({ tracking: outcome(pressStatusItem, -25204),"
            " opened: outcome(pressStatusItem, 0),"
            " failed: outcome(pressStatusItem, -25200),"
            " menu: outcome(pressMenuElement, -25204) })"
        )
        result = subprocess.run(
            ["osascript", "-l", "JavaScript", "-e", harness],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            json.loads(result.stdout),
            {
                "tracking": "timeout 0.5, AXPress, timeout 0",
                "opened": "timeout 0.5, AXPress, timeout 0",
                "failed": "timeout 0.5, AXPress, timeout 0 -> AXPress failed with AXError -25200",
                "menu": "AXPress -> AXPress failed with AXError -25204",
            },
        )

    def test_capture_probes_after_finding_the_app_and_before_any_gui_call(
        self,
    ) -> None:
        order: list[str] = []
        with (
            patch.object(
                capture, "process_id", side_effect=lambda: order.append("pid") or 7
            ),
            patch.object(
                capture,
                "ax",
                side_effect=lambda *call: order.append("probe") or "-25211",
            ),
            patch.object(capture, "session_state", return_value=UNLOCKED),
            patch.object(capture, "gui") as gui,
            self.assertRaises(capture.CaptureError),
        ):
            capture.capture(capture.parse_args(["--area", "Controllers"]))
        self.assertEqual(order, ["pid", "probe"])
        gui.assert_not_called()

    def session_message(self, reported: str) -> str | None:
        with patch.object(capture, "session_state", return_value=reported):
            try:
                capture.require_unlocked_console_session()
            except capture.CaptureError as error:
                return str(error)
        return None

    def test_unlocked_console_session_lets_capture_continue(self) -> None:
        self.assertIsNone(self.session_message(UNLOCKED))

    def test_locked_screen_is_named(self) -> None:
        message = self.session_message("locked=true console=true")
        assert message is not None
        self.assertIn("the screen is locked: unlock this Mac's session", message)

    def test_session_off_the_console_is_named(self) -> None:
        message = self.session_message("locked=false console=false")
        assert message is not None
        self.assertIn("not on the console", message)
        self.assertNotIn("screen is locked", message)

    def test_unreadable_session_state_fails(self) -> None:
        message = self.session_message("garbage")
        assert message is not None
        self.assertIn("session state reported 'garbage'", message)

    def test_locked_screen_stops_before_the_accessibility_probe(self) -> None:
        with (
            patch.object(capture, "process_id", return_value=7),
            patch.object(
                capture, "session_state", return_value="locked=true console=true"
            ),
            patch.object(capture, "ax") as probe,
            self.assertRaises(capture.CaptureError),
        ):
            capture.capture(capture.parse_args(["--area", "Controllers"]))
        probe.assert_not_called()

    def test_english_ui_is_required(self) -> None:
        english = self.completed(0, '(\n    "en-US",\n    "et-EE"\n)')
        german = self.completed(0, '(\n    "de-DE",\n    "en-US"\n)')
        unset = self.completed(1, "")
        with patch.object(capture.subprocess, "run", side_effect=[unset, english]):
            capture.require_english_ui()
        with (
            patch.object(capture.subprocess, "run", side_effect=[german]),
            self.assertRaisesRegex(capture.CaptureError, "de-DE"),
        ):
            capture.require_english_ui()
        with (
            patch.object(capture.subprocess, "run", side_effect=[unset, unset]),
            self.assertRaises(capture.CaptureError),
        ):
            capture.require_english_ui()

    def test_read_state_parses_and_validates(self) -> None:
        for reported, expected in (
            ("main=true settings=none", (True, None)),
            ("main=false settings=Advanced", (False, "Advanced")),
        ):
            with patch.object(capture, "gui", return_value=reported):
                self.assertEqual(capture.read_state(), expected)
        for reported in ("garbage", "main=true settings=Elsewhere"):
            with (
                patch.object(capture, "gui", return_value=reported),
                self.assertRaises(capture.CaptureError),
            ):
                capture.read_state()

    def test_bring_forward_raises_the_window_until_nothing_covers_it(self) -> None:
        covered = [self.window(id=3, pid=7, owner="Code", x=200), self.window()]
        clear = [self.window()]
        reads = [covered, covered, clear]
        calls: list[tuple[str, ...]] = []

        def fake_gui(*command: str) -> str:
            calls.append(command)
            return "10 20 300 200"

        clock, sleep = self.fake_time()
        with (
            patch.object(capture, "gui", side_effect=fake_gui),
            patch.object(capture, "on_screen_windows", side_effect=reads),
        ):
            found = capture.bring_forward(1, "main", 5.0, clock, sleep)
        self.assertEqual(found["id"], 9)
        raises = [call for call in calls if call[0] == "raise"]
        self.assertEqual(raises, [("raise", "main")] * 3)
        self.assertEqual(clock(), 2 * capture.FRONT_POLL_SECONDS)

    def test_bring_forward_gives_up_at_the_deadline_naming_the_owners(self) -> None:
        covered = [
            self.window(id=3, pid=7, owner="Code", x=200),
            self.window(id=4, pid=8, owner="Finder", x=100),
            self.window(),
        ]
        clock, sleep = self.fake_time()
        with (
            patch.object(capture, "gui", return_value="10 20 300 200"),
            patch.object(capture, "on_screen_windows", return_value=covered),
            self.assertRaises(capture.CaptureError) as raised,
        ):
            capture.bring_forward(1, "settings", 1.0, clock, sleep)
        message = str(raised.exception)
        self.assertIn(
            "the settings window is covered by windows of Code, Finder after 1 s of "
            "bringing the app forward (--front-timeout)",
            message,
        )
        self.assertLessEqual(clock(), 1.0)

    def test_covered_window_is_never_captured(self) -> None:
        commands: list[list[str]] = []

        def fake_run(command: list[str]) -> str:
            commands.append(command)
            return json.dumps([self.window(id=3, pid=7, owner="Code"), self.window()])

        clock, sleep = self.fake_time()
        with (
            patch.object(capture, "run", side_effect=fake_run),
            patch.object(capture, "gui", return_value="10 20 300 200"),
            self.assertRaises(capture.CaptureError),
        ):
            capture.shoot(1, "main", Path("/nonexistent/main.png"), 1.0, clock, sleep)
        self.assertEqual(
            [command for command in commands if command[0] == "screencapture"], []
        )

    def test_help_names_each_timeout_default(self) -> None:
        with (
            patch.object(capture.sys, "stdout") as stdout,
            self.assertRaises(SystemExit),
        ):
            capture.parse_args(["--help"])
        text = " ".join(
            "".join(call.args[0] for call in stdout.write.call_args_list).split()
        )
        self.assertIn(f"(default {capture.FRONT_TIMEOUT_SECONDS:g})", text)
        self.assertIn(f"(default {capture.APP_READY_TIMEOUT_SECONDS:g})", text)

    def test_front_timeout_option_is_positive(self) -> None:
        self.assertEqual(
            capture.parse_args(["--all", "--front-timeout", "2"]).front_timeout, 2.0
        )
        self.assertEqual(
            capture.parse_args(["--all"]).front_timeout, capture.FRONT_TIMEOUT_SECONDS
        )
        for value in ("0", "-1", "nan", "inf"):
            with self.subTest(value=value), self.assertRaises(SystemExit):
                capture.parse_args(["--all", "--front-timeout", value])

    def test_menus_is_one_of_the_exclusive_choices(self) -> None:
        self.assertTrue(capture.parse_args(["--menus"]).menus)
        self.assertFalse(capture.parse_args(["--all"]).menus)
        for argv in (["--menus", "--all"], ["--menus", "--area", "Library"]):
            with self.subTest(argv=argv), self.assertRaises(SystemExit):
                capture.parse_args(argv)

    def menu_window(self, **fields: object) -> dict:
        return self.window(layer=capture.MENU_LAYER, **fields)

    def test_union_rectangle_spans_the_parent_menu_and_its_submenu(self) -> None:
        parent = self.menu_window(id=1, x=100, y=33, width=200, height=300)
        submenu = self.menu_window(id=2, x=300, y=120, width=150, height=500)
        self.assertEqual(
            capture.union_rectangle([parent, submenu]),
            {"x": 100, "y": 33, "width": 350, "height": 587},
        )
        self.assertEqual(
            capture.screen_rectangle(capture.union_rectangle([parent, submenu])),
            "100,33,350,587",
        )
        # A submenu that opens to the left of its parent extends the rectangle to the left.
        left = self.menu_window(id=3, x=-20, y=40, width=120, height=100)
        self.assertEqual(capture.union_rectangle([parent, left])["x"], -20)
        self.assertEqual(capture.union_rectangle([parent])["width"], 200)

    def test_union_rectangle_refuses_no_window(self) -> None:
        with self.assertRaises(capture.CaptureError):
            capture.union_rectangle([])

    def test_menu_windows_are_the_popup_layer_windows_of_the_app(self) -> None:
        menu = self.menu_window(id=1)
        windows = [
            self.menu_window(id=2, pid=2, owner="Safari"),
            menu,
            self.window(id=3),
            self.window(id=4, layer=25),
        ]
        self.assertEqual(capture.menu_windows(1, windows), [menu])

    def test_menu_targets_follow_the_menu_bar_order(self) -> None:
        ids = [
            "menu.app",
            "menu.file",
            "menu.edit",
            "menu.view",
            "menu.controller",
            "menu.profile",
            "menu.window",
            "menu.help",
        ]
        targets = capture.menu_targets(ids)
        self.assertEqual(
            [target.name for target in targets],
            [
                "menu-app",
                "menu-file",
                "menu-edit",
                "menu-view",
                "menu-controller",
                "menu-profile",
                "menu-profile-activate-profile",
                "menu-window",
                "menu-help",
                "menu-status-item",
            ],
        )
        by_name = {target.name: target for target in targets}
        self.assertEqual(
            by_name["menu-profile-activate-profile"].path,
            ("menu.profile", "activateProfile"),
        )
        self.assertEqual(
            [by_name[name].depth for name in by_name],
            [1, 1, 1, 1, 1, 1, 2, 1, 1, 1],
        )
        self.assertTrue(by_name["menu-status-item"].status_item)
        self.assertFalse(by_name["menu-help"].status_item)

    def test_menu_targets_refuse_a_menu_bar_without_a_profile_menu(self) -> None:
        with self.assertRaisesRegex(capture.CaptureError, "no menu.profile menu"):
            capture.menu_targets(["menu.app", "menu.file"])
        with self.assertRaisesRegex(capture.CaptureError, "identifier"):
            capture.menu_targets([""])
        with self.assertRaisesRegex(capture.CaptureError, "'Profile'"):
            capture.menu_targets(["menu.profile", "Profile"])

    def test_menu_targets_refuse_identifiers_with_one_file_name(self) -> None:
        with self.assertRaisesRegex(capture.CaptureError, "menu-view"):
            capture.menu_targets(["menu.profile", "menu.view", "menu.View"])

    def test_menu_identifiers_are_the_ones_the_swift_menu_model_sets(self) -> None:
        sources = capture.PROJECT_DIR / "Sources" / "OpenJoystickDriverPresentation"
        main_menu = (sources / "MainMenu" / "MainMenuModel.swift").read_text()
        renderer = (sources / "MainMenu" / "MainMenuRenderer.swift").read_text()
        status = (sources / "MenuBar" / "StatusItemModel.swift").read_text()
        status_menu = (
            sources / "MenuBar" / "MenuBarCoordinator+StatusMenu.swift"
        ).read_text()
        section = capture.PROFILE_MENU_ID.removeprefix(capture.MENU_BAR_ID_PREFIX)
        self.assertIn(f'"{capture.MENU_BAR_ID_PREFIX}\\(sectionID)"', main_menu)
        self.assertIn(f'id: "{section}"', main_menu)
        self.assertIn(f'"{capture.ACTIVATE_PROFILE_ID}"', main_menu)
        self.assertIn("menuBarItemIdentifier(sectionID: section.id)", renderer)
        self.assertIn("setAccessibilityIdentifier(id)", renderer)
        self.assertIn("identify(item, as: entry.id)", status_menu)

    def test_menu_commands_open_the_menu_bar_item_or_the_status_item(self) -> None:
        main = capture.MenuTarget("menu-profile", ("menu.profile",))
        sub = capture.MenuTarget(
            "menu-profile-activate-profile", ("menu.profile", "activateProfile")
        )
        status = capture.MenuTarget("menu-status-item", (), status_item=True)
        status_sub = capture.MenuTarget(
            "x", ("controller.a", "controller.a.pause"), status_item=True
        )
        self.assertEqual(capture.open_menu_command(main), ("open-menu", "menu.profile"))
        self.assertEqual(
            capture.open_menu_command(sub),
            ("open-menu", "menu.profile", "activateProfile"),
        )
        self.assertEqual(capture.open_menu_command(status), ("open-status-menu",))
        self.assertEqual(
            capture.open_menu_command(status_sub),
            ("open-status-menu", "controller.a", "controller.a.pause"),
        )

    def test_ax_command_line_carries_every_menu_argument(self) -> None:
        with patch.object(capture, "run", return_value="") as run:
            capture.ax("open-menu", 7, "menu.profile", "activateProfile")
        run.assert_called_once_with(
            [
                "osascript",
                "-l",
                "JavaScript",
                str(capture.GUI_DIR / "ax.js"),
                "open-menu",
                "7",
                "menu.profile",
                "activateProfile",
            ]
        )

    def wait_for_menu_with(
        self, reads: list[list[dict]], depth: int
    ) -> tuple[list[dict] | None, str | None, int]:
        clock, sleep = self.fake_time()
        with patch.object(
            capture, "on_screen_windows", side_effect=reads * 200
        ) as listing:
            try:
                menus, _ = capture.wait_for_menu(1, depth, clock, sleep)
            except capture.CaptureError as error:
                return None, str(error), listing.call_count
        return menus, None, listing.call_count

    def test_menu_wait_returns_after_two_equal_reads(self) -> None:
        parent = self.menu_window(id=1)
        submenu = self.menu_window(id=2, x=300)
        moving = self.menu_window(id=2, x=290)
        menus, error, reads = self.wait_for_menu_with(
            [[], [parent], [parent, moving], [parent, submenu], [parent, submenu]], 2
        )
        self.assertIsNone(error)
        self.assertEqual(menus, [parent, submenu])
        self.assertEqual(reads, 5)

    def test_menu_wait_names_how_many_menus_never_appeared(self) -> None:
        menus, error, _ = self.wait_for_menu_with([[self.menu_window(id=1)]], 2)
        self.assertIsNone(menus)
        assert error is not None
        self.assertIn(
            "1 menu windows of OpenJoystickDriver were on screen where 2", error
        )
        self.assertIn(f"{capture.MENU_TIMEOUT_SECONDS:g} s", error)

    def test_menu_wait_refuses_more_menus_than_it_opened(self) -> None:
        # A menu left open by another action would join the image.
        extra = [self.menu_window(id=1), self.menu_window(id=2, x=300)]
        menus, error, _ = self.wait_for_menu_with([extra], 1)
        self.assertIsNone(menus)
        assert error is not None
        self.assertIn(
            "2 menu windows of OpenJoystickDriver were on screen where 1", error
        )

    def test_menu_wait_waits_for_a_fading_menu(self) -> None:
        fading = self.menu_window(id=1, alpha=0.5)
        shown = self.menu_window(id=1)
        menus, error, reads = self.wait_for_menu_with([[fading], [shown], [shown]], 1)
        self.assertIsNone(error)
        self.assertEqual(menus, [shown])
        self.assertEqual(reads, 3)

    def test_menu_wait_refuses_a_menu_that_never_settles(self) -> None:
        flicker = [[self.menu_window(id=1, x=index)] for index in range(10_000)]
        clock, sleep = self.fake_time()
        with (
            patch.object(capture, "on_screen_windows", side_effect=flicker),
            self.assertRaises(capture.CaptureError),
        ):
            capture.wait_for_menu(1, 1, clock, sleep)

    def test_close_menu_presses_escape_until_no_menu_window_is_left(self) -> None:
        open_menus = [self.menu_window(id=1)]
        reads = [open_menus, open_menus, [], []]
        clock, sleep = self.fake_time()
        with (
            patch.object(capture, "on_screen_windows", side_effect=reads),
            patch.object(capture, "gui") as gui,
        ):
            capture.close_menu(1, clock, sleep)
        gui.assert_called_once_with("press-escape")

    def test_close_menu_presses_again_once_the_submenu_closed(self) -> None:
        parent = self.menu_window(id=1)
        both = [parent, self.menu_window(id=2, x=300)]
        reads = [both, [parent], [parent], [], []]
        clock, sleep = self.fake_time()
        with (
            patch.object(capture, "on_screen_windows", side_effect=reads),
            patch.object(capture, "gui") as gui,
        ):
            capture.close_menu(1, clock, sleep)
        self.assertEqual(gui.call_count, 2)
        # Neither press waited out the settle time: each saw one fewer menu at once.
        self.assertEqual(clock(), 0.0)

    def test_close_menu_without_an_open_menu_presses_nothing(self) -> None:
        clock, sleep = self.fake_time()
        with (
            patch.object(capture, "on_screen_windows", return_value=[self.window()]),
            patch.object(capture, "gui") as gui,
        ):
            capture.close_menu(1, clock, sleep)
        gui.assert_not_called()

    def test_close_menu_gives_up_after_the_escape_presses(self) -> None:
        stuck = [self.menu_window(id=1)]
        clock, sleep = self.fake_time()
        with (
            patch.object(capture, "on_screen_windows", return_value=stuck),
            patch.object(capture, "gui") as gui,
            self.assertRaisesRegex(capture.CaptureError, "still open after 4 Escape"),
        ):
            capture.close_menu(1, clock, sleep)
        self.assertEqual(gui.call_count, capture.ESCAPE_PRESSES)

    def shoot_menu_with(
        self, target: capture.MenuTarget, reads: list[list[dict]]
    ) -> tuple[list[object], Path, Exception | None]:
        events: list[object] = []
        folder = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, folder)

        def fake_run(command: list[str]) -> str:
            events.append(command)
            if command[0] == "screencapture":
                Path(command[-1]).write_bytes(b"png")
            return ""

        def fake_gui(*command: str) -> str:
            events.append(command)
            return ""

        clock, sleep = self.fake_time()
        failure: Exception | None = None
        with (
            patch.object(capture, "run", side_effect=fake_run),
            patch.object(
                capture.repository_tool,
                "binary",
                return_value=Path("/tool/OJDRepositoryTool"),
            ),
            patch.object(capture, "gui", side_effect=fake_gui),
            patch.object(capture, "on_screen_windows", side_effect=reads),
            patch("builtins.print"),
            patch.object(capture.sys, "stderr"),
        ):
            try:
                capture.shoot_menu(1, target, folder / "menu.png", clock, sleep)
            except capture.CaptureError as error:
                failure = error
        return events, folder, failure

    def test_shoot_menu_captures_the_union_then_closes_with_escape(self) -> None:
        parent = self.menu_window(id=1, x=100, y=33, width=200, height=300)
        submenu = self.menu_window(id=2, x=300, y=120, width=150, height=500)
        both = [parent, submenu]
        target = capture.MenuTarget("menu-profile", ("menu.profile", "activateProfile"))
        # No menu before the open; two reads settle the menus; close_menu reads them open,
        # then one fewer, then none.
        events, folder, failure = self.shoot_menu_with(
            target, [[], both, both, both, [parent], [parent], [], []]
        )
        self.assertIsNone(failure)
        self.assertEqual(
            events,
            [
                ("open-menu", "menu.profile", "activateProfile"),
                [
                    "screencapture",
                    "-x",
                    "-R",
                    "100,33,350,587",
                    str(folder / "menu.png"),
                ],
                [
                    "/tool/OJDRepositoryTool",
                    "mask-image",
                    str(folder / "menu.png"),
                    "100,33,350,587",
                    "100,33,200,300",
                    "300,120,150,500",
                ],
                ("press-escape",),
                ("press-escape",),
            ],
        )

    def test_a_submenu_over_its_parent_menu_does_not_cover_it(self) -> None:
        parent = self.menu_window(id=1, x=100, y=33, width=200, height=300)
        submenu = self.menu_window(id=2, x=294, y=120, width=150, height=500)
        both = [submenu, parent]
        target = capture.MenuTarget("menu-profile", ("menu.profile", "activateProfile"))
        _, _, failure = self.shoot_menu_with(
            target, [[], both, both, both, [parent], [parent], [], []]
        )
        self.assertIsNone(failure)

    def test_the_other_menus_leave_the_window_list_in_front_to_back_order(self) -> None:
        parent = self.menu_window(id=1, x=100, y=33, width=200, height=300)
        submenu = self.menu_window(id=2, x=294, y=120, width=150, height=500)
        cover = self.window(id=3, pid=7, owner="Code", x=150, y=100, layer=102)
        behind = self.window(id=4, pid=8, owner="Finder")
        windows = [submenu, cover, parent, behind]
        # Copies, as from another read of the window list: windows match by id.
        menus = [dict(parent), dict(submenu)]
        self.assertEqual(
            capture.without_other_menus(menus[0], menus, windows),
            [cover, parent, behind],
        )
        self.assertEqual(
            capture.without_other_menus(menus[1], menus, windows),
            [submenu, cover, behind],
        )

    def test_a_window_between_a_submenu_and_its_parent_covers_the_parent(self) -> None:
        parent = self.menu_window(id=1, x=100, y=33, width=200, height=300)
        submenu = self.menu_window(id=2, x=294, y=120, width=150, height=500)
        cover = self.window(id=3, pid=7, owner="Code", x=150, y=100, layer=102)
        covered = [submenu, cover, parent]
        target = capture.MenuTarget("menu-profile", ("menu.profile", "activateProfile"))
        _, _, failure = self.shoot_menu_with(
            target, [[], covered, covered, covered, [], []]
        )
        assert failure is not None
        self.assertIn(
            "the menu-profile menu is covered by windows of Code", str(failure)
        )

    def test_shoot_menu_refuses_a_menu_that_is_already_open(self) -> None:
        stale = [self.menu_window(id=5)]
        target = capture.MenuTarget("menu-file", ("menu.file",))
        events, _, failure = self.shoot_menu_with(target, [stale])
        assert failure is not None
        self.assertIn(
            "1 menu windows of OpenJoystickDriver are open before", str(failure)
        )
        self.assertEqual(events, [])

    def test_shoot_menu_refuses_a_covered_menu_and_still_closes_it(self) -> None:
        menu = self.menu_window(id=1, x=100, y=33, width=200, height=300)
        cover = self.window(id=3, pid=7, owner="Code", x=150, y=100, layer=102)
        covered = [cover, menu]
        target = capture.MenuTarget("menu-file", ("menu.file",))
        events, _, failure = self.shoot_menu_with(
            target, [[], covered, covered, covered, [], []]
        )
        assert failure is not None
        self.assertIn(
            "the menu-file menu is covered by windows of Code once it opened",
            str(failure),
        )
        self.assertEqual(events, [("open-menu", "menu.file"), ("press-escape",)])

    def test_shoot_menu_refuses_when_the_menu_never_opens(self) -> None:
        target = capture.MenuTarget("menu-status-item", (), status_item=True)
        events, _, failure = self.shoot_menu_with(target, [[]] * 200)
        assert failure is not None
        self.assertIn(
            "0 menu windows of OpenJoystickDriver were on screen where 1", str(failure)
        )
        self.assertEqual(events, [("open-status-menu",)])

    def run_menu_capture(
        self,
        argv: list[str],
        ids: str,
        english: object = None,
        tool: Exception | None = None,
    ) -> tuple[list, list]:
        shots: list[str] = []
        calls: list[tuple[str, ...]] = []

        def fake_binary() -> Path:
            calls.append(("build OJDRepositoryTool",))
            if tool is not None:
                raise tool
            return Path("/tool/OJDRepositoryTool")

        def fake_gui(*command: str) -> str:
            calls.append(command)
            if command[0] == "menu-ids":
                return ids
            return "Activity" if command[0] == "current-sidebar" else ""

        with (
            tempfile.TemporaryDirectory() as root,
            patch.object(capture, "PROJECT_DIR", Path(root)),
            patch.object(capture, "process_id", return_value=1),
            patch.object(capture, "require_unlocked_console_session"),
            patch.object(capture, "require_accessibility"),
            patch.object(capture, "require_english_ui", side_effect=english),
            patch.object(capture, "run"),
            patch.object(capture, "read_state", return_value=(True, None)),
            patch.object(capture, "gui", side_effect=fake_gui),
            patch.object(capture.repository_tool, "binary", side_effect=fake_binary),
            patch.object(capture, "shoot"),
            patch.object(
                capture,
                "shoot_menu",
                side_effect=lambda pid, target, destination: shots.append(
                    f"{target.name}={destination.name}"
                ),
            ),
            patch.object(capture.sys, "stderr"),
        ):
            capture.capture(capture.parse_args(argv))
        return shots, calls

    def test_menus_capture_writes_one_png_per_menu_named_like_the_other_shots(
        self,
    ) -> None:
        shots, _ = self.run_menu_capture(["--menus"], "menu.file\nmenu.profile")
        self.assertEqual(
            shots,
            [
                "menu-file=menu-file.png",
                "menu-profile=menu-profile.png",
                "menu-profile-activate-profile=menu-profile-activate-profile.png",
                "menu-status-item=menu-status-item.png",
            ],
        )

    def test_all_includes_the_menus_and_an_area_does_not(self) -> None:
        all_shots, _ = self.run_menu_capture(["--all"], "menu.profile")
        self.assertIn("menu-profile=menu-profile.png", all_shots)
        area_shots, calls = self.run_menu_capture(["--area", "Library"], "menu.profile")
        self.assertEqual(area_shots, [])
        self.assertNotIn(("menu-ids",), calls)
        self.assertNotIn(("build OJDRepositoryTool",), calls)

    def test_menus_capture_builds_the_mask_tool_before_it_drives_the_app(self) -> None:
        _, calls = self.run_menu_capture(["--menus"], "menu.profile")
        self.assertEqual(calls[0], ("build OJDRepositoryTool",))

    def test_a_mask_tool_that_does_not_build_stops_the_menus_capture(self) -> None:
        failure = capture.repository_tool.ToolError(
            "cannot build OJDRepositoryTool: no"
        )
        with self.assertRaisesRegex(
            capture.CaptureError, "cannot build OJDRepositoryTool: no"
        ):
            self.run_menu_capture(["--menus"], "menu.profile", tool=failure)

    def test_only_sidebar_and_settings_captures_need_an_english_ui(self) -> None:
        refused = capture.CaptureError("the app UI language is de-DE")
        shots, _ = self.run_menu_capture(["--menus"], "menu.profile", english=refused)
        self.assertIn("menu-profile=menu-profile.png", shots)
        for argv in (["--all"], ["--area", "Library"], ["--settings-pane", "General"]):
            with (
                self.subTest(argv=argv),
                self.assertRaisesRegex(capture.CaptureError, "de-DE"),
            ):
                self.run_menu_capture(argv, "menu.profile", english=refused)

    def test_menus_capture_without_a_profile_menu_fails_by_name(self) -> None:
        with self.assertRaisesRegex(capture.CaptureError, "no menu.profile menu"):
            self.run_menu_capture(["--menus"], "menu.app\nmenu.file")

    @unittest.skipUnless(
        shutil.which("osacompile"), "osacompile is not installed: ax.js needs JXA"
    )
    def test_ax_script_compiles(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            result = subprocess.run(
                [
                    "osacompile",
                    "-l",
                    "JavaScript",
                    "-o",
                    str(Path(folder) / "ax.scpt"),
                    str(capture.GUI_DIR / "ax.js"),
                ],
                capture_output=True,
                text=True,
                check=False,
            )
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
