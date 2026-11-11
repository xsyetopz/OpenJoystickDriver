from __future__ import annotations

import argparse
import json
import subprocess
import sys
import threading
import time
import uuid
from dataclasses import dataclass
from datetime import datetime
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, cast

PROJECT_DIR = Path(__file__).resolve().parents[2]
PAGE = Path(__file__).resolve().with_name("browser_gamepad.html")
OJD_APP_CLI = "/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver"
OUTPUT_ROOT = PROJECT_DIR / ".build" / "browser-gamepad"
BROWSERS = {"firefox": "Firefox", "chrome": "Google Chrome", "safari": "Safari"}
PRESS_MS = 600
REST_MS = 1400
SETTLE_MS = 2000
WAKE_MS = 3000
READY_TIMEOUT_SECONDS = 15.0
DRAIN_SECONDS = 1.5
ANALOG_THRESHOLD = 0.5

Event = dict[str, Any]


@dataclass(frozen=True)
class Control:
    name: str
    frame: Event
    expected: str


def _button(name: str, feed: str, index: int) -> Control:
    return Control(name, {"buttons": [feed]}, f"b{index}")


def _axis(name: str, feed: str, value: int, index: int) -> Control:
    return Control(
        name, {"axes": {feed: value}}, f"a{index}{'+' if value > 0 else '-'}"
    )


CONTROLS: tuple[Control, ...] = (
    _button("A", "South", 0),
    _button("B", "East", 1),
    _button("X", "West", 2),
    _button("Y", "North", 3),
    _button("LB", "LeftShoulder", 4),
    _button("RB", "RightShoulder", 5),
    Control("LT", {"axes": {"LeftTrigger": 1}}, "b6"),
    Control("RT", {"axes": {"RightTrigger": 1}}, "b7"),
    _button("View", "Back", 8),
    _button("Menu", "Start", 9),
    _button("L3", "LeftStickClick", 10),
    _button("R3", "RightStickClick", 11),
    Control("Up", {"dpad": ["DpadUp"]}, "b12"),
    Control("Down", {"dpad": ["DpadDown"]}, "b13"),
    Control("Left", {"dpad": ["DpadLeft"]}, "b14"),
    Control("Right", {"dpad": ["DpadRight"]}, "b15"),
    _button("Guide", "Guide", 16),
    _button("Share", "Capture", 17),
    _axis("Left stick right", "LeftStickX", 1, 0),
    _axis("Left stick left", "LeftStickX", -1, 0),
    _axis("Left stick up", "LeftStickY", -1, 1),
    _axis("Left stick down", "LeftStickY", 1, 1),
    _axis("Right stick right", "RightStickX", 1, 2),
    _axis("Right stick left", "RightStickX", -1, 2),
    _axis("Right stick up", "RightStickY", -1, 3),
    _axis("Right stick down", "RightStickY", 1, 3),
)


def feed_frames() -> list[Event]:
    frames: list[Event] = [
        {"holdMilliseconds": SETTLE_MS},
        {"buttons": ["South"], "holdMilliseconds": PRESS_MS},
        {"holdMilliseconds": WAKE_MS - PRESS_MS},
    ]
    for control in CONTROLS:
        frames.append({**control.frame, "holdMilliseconds": PRESS_MS})
        frames.append({"holdMilliseconds": REST_MS})
    return frames


def readings(event: Event) -> set[str]:
    found: set[str] = set()
    for index, value in event.get("buttons", []):
        if value >= ANALOG_THRESHOLD:
            found.add(f"b{index}")
    for index, value in enumerate(event.get("axes", [])):
        if abs(value) >= ANALOG_THRESHOLD:
            found.add(f"a{index}{'+' if value > 0 else '-'}")
    return found


def _steps(states: list[Event], first_step_ms: int) -> list[Event]:
    step_ms = PRESS_MS + REST_MS
    seen: list[set[str]] = [set() for _ in CONTROLS]
    for event in states:
        step = (int(event["t"]) - first_step_ms + REST_MS // 2) // step_ms
        if 0 <= step < len(CONTROLS):
            seen[step] |= readings(event)
    return [
        {
            "control": control.name,
            "expected": control.expected,
            "seen": sorted(slots),
            "status": "ok"
            if slots == {control.expected}
            else "missing"
            if not slots
            else "differs",
        }
        for control, slots in zip(CONTROLS, seen, strict=True)
    ]


def classify(events: list[Event], feed_start_ms: int, feed_end_ms: int) -> Event:
    during = [e for e in events if feed_start_ms <= e["t"] < feed_end_ms]
    woken = [e for e in during if e.get("ev") == "state" and "b0" in readings(e)]
    if not woken:
        return {"connected": None, "controls": [], "rumble": None}
    index = woken[0]["i"]
    pad = next(
        (e for e in events if e.get("ev") == "connected" and e.get("i") == index),
        woken[0],
    )
    states = [e for e in during if e.get("i") == index and e.get("ev") == "state"]
    presses = [int(e["t"]) for e in woken if e.get("i") == index]
    candidates = sorted({t + offset for t in presses for offset in (0, WAKE_MS)})
    controls = max(
        (_steps(states, start) for start in candidates),
        key=lambda rows: sum(row["status"] == "ok" for row in rows),
    )
    rumble = next(
        (
            e.get("result")
            for e in during
            if e.get("i") == index and e.get("ev") == "rumble"
        ),
        None,
    )
    return {
        "connected": {key: pad.get(key) for key in ("id", "mapping", "nb", "na")},
        "controls": controls,
        "rumble": rumble,
    }


class _LogServer(ThreadingHTTPServer):
    def __init__(self, log: Path) -> None:
        self.log = log
        self.lock = threading.Lock()
        self.events: list[Event] = []
        super().__init__(("127.0.0.1", 0), _Handler)


class _Handler(SimpleHTTPRequestHandler):
    def do_GET(self) -> None:
        body = PAGE.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self) -> None:
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        event = json.loads(body)
        server = cast(_LogServer, self.server)
        with server.lock:
            server.events.append(event)
            with server.log.open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(event) + "\n")
        self.send_response(204)
        self.end_headers()

    def log_message(self, format: str, *args: object) -> None:
        return


def _wait_for_ready(server: _LogServer, run: str) -> bool:
    deadline = time.monotonic() + READY_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        with server.lock:
            if any(
                e.get("run") == run and e.get("ev") == "ready" for e in server.events
            ):
                return True
        time.sleep(0.1)
    return False


def _installed(app: str) -> bool:
    return (
        subprocess.run(
            ["open", "-Ra", app], check=False, capture_output=True
        ).returncode
        == 0
    )


def _test_browser(
    server: _LogServer, key: str, persona: str | None, frames: str
) -> Event:
    app = BROWSERS[key]
    if not _installed(app):
        return {"browser": key, "skipped": f"{app} is not installed"}
    run = f"{key}-{uuid.uuid4().hex[:8]}"
    port = server.server_address[1]
    subprocess.run(
        ["open", "-a", app, f"http://127.0.0.1:{port}/?run={run}"], check=True
    )
    if not _wait_for_ready(server, run):
        return {
            "browser": key,
            "failed": f"{app} did not load the page in {READY_TIMEOUT_SECONDS:.0f} s",
        }
    feed = ["ojd", "virtual", "feed", *(["--as", persona] if persona else [])]
    start_ms = int(time.time() * 1000)
    result = subprocess.run(
        feed,
        check=False,
        executable=OJD_APP_CLI,
        input=frames,
        text=True,
        capture_output=True,
    )
    end_ms = int(time.time() * 1000)
    time.sleep(DRAIN_SECONDS)
    if result.returncode != 0:
        return {
            "browser": key,
            "failed": f"ojd virtual feed exited {result.returncode}: {result.stderr.strip()}",
        }
    with server.lock:
        events = [e for e in server.events if e.get("run") == run]
    user_agent = next((e["ua"] for e in events if "ua" in e), None)
    return {
        "browser": key,
        "userAgent": user_agent,
        **classify(events, start_ms, end_ms),
    }


def _print_result(result: Event) -> None:
    print(f"== {result['browser']}")
    for reason in ("skipped", "failed"):
        if reason in result:
            print(f"   {reason}: {result[reason]}")
            return
    print(f"   {result['userAgent']}")
    if result["connected"] is None:
        print("   failed: no pad showed the wake press of A")
        return
    print(f"   pad: {json.dumps(result['connected'])}  rumble: {result['rumble']}")
    for row in result["controls"]:
        print(
            f"   {row['status']:<8} {row['control']:<18} expected {row['expected']:<4} seen {','.join(row['seen']) or '-'}"
        )


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="just diagnose-browsers")
    parser.add_argument(
        "--as", dest="persona", help="persona for `ojd virtual feed --as`"
    )
    parser.add_argument(
        "--browsers",
        default=",".join(BROWSERS),
        help=f"comma-separated browsers to test, from {', '.join(BROWSERS)} (default: all)",
    )
    args = parser.parse_args(argv)
    keys = args.browsers.split(",")
    unknown = [key for key in keys if key not in BROWSERS]
    if unknown:
        parser.error(f"unknown browser: {', '.join(unknown)}")
    if not Path(OJD_APP_CLI).is_file():
        print(
            f"error: OpenJoystickDriver is not installed at {OJD_APP_CLI}",
            file=sys.stderr,
        )
        return 1
    output = OUTPUT_ROOT / datetime.now().strftime("%Y%m%d-%H%M%S")
    output.mkdir(parents=True)
    server = _LogServer(output / "events.jsonl")
    threading.Thread(target=server.serve_forever, daemon=True).start()
    frames = "".join(json.dumps(frame) + "\n" for frame in feed_frames())
    try:
        results = [_test_browser(server, key, args.persona, frames) for key in keys]
    finally:
        server.shutdown()
    for result in results:
        _print_result(result)
    (output / "results.json").write_text(
        json.dumps(results, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Wrote {output / 'results.json'} and {output / 'events.jsonl'}")
    return (
        1
        if any("failed" in r or r.get("connected", True) is None for r in results)
        else 0
    )


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
