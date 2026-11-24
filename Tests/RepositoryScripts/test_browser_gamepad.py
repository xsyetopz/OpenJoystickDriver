from __future__ import annotations

import unittest

from Scripts.Diagnostics import browser_gamepad as harness
from Scripts.Diagnostics.browser_gamepad import Event

STEP_MS = harness.PRESS_MS + harness.REST_MS


def state(
    t: int, pad: int, buttons: list[list[float]], axes: list[float] | None = None
) -> Event:
    return {
        "ev": "state",
        "t": t,
        "i": pad,
        "buttons": buttons,
        "axes": axes or [0, 0, 0, 0],
    }


def press(control: harness.Control, t: int, pad: int) -> Event:
    slot = control.expected
    if slot.startswith("b"):
        return state(t, pad, [[int(slot[1:]), 1.0]])
    axes = [0.0, 0.0, 0.0, 0.0]
    axes[int(slot[1])] = 1.0 if slot.endswith("+") else -1.0
    return state(t, pad, [], axes)


def run(first_step_ms: int, *, wake: bool, pad: int = 2) -> list[Event]:
    events: list[Event] = [
        {"ev": "connected", "t": 900, "i": 0, "id": "physical"},
        {
            "ev": "connected",
            "t": 900,
            "i": pad,
            "id": "fed",
            "mapping": "standard",
            "nb": 18,
            "na": 4,
        },
        state(950, 0, []),
    ]
    if wake:
        events.append(state(first_step_ms - harness.WAKE_MS, pad, [[0, 1.0]]))
        events.append(
            {
                "ev": "rumble",
                "t": first_step_ms - harness.WAKE_MS + 100,
                "i": pad,
                "result": "complete",
            }
        )
    for step, control in enumerate(harness.CONTROLS):
        start = first_step_ms + step * STEP_MS + 40
        events.append(press(control, start, pad))
        events.append(state(start + harness.PRESS_MS, pad, []))
    return events


class BrowserGamepadHarnessTests(unittest.TestCase):
    def test_the_feed_rests_wakes_and_then_steps_through_every_control(self) -> None:
        frames = harness.feed_frames()
        self.assertEqual(frames[0], {"holdMilliseconds": harness.SETTLE_MS})
        self.assertEqual(
            frames[1], {"buttons": ["South"], "holdMilliseconds": harness.PRESS_MS}
        )
        self.assertEqual(len(frames), 3 + 2 * len(harness.CONTROLS))
        self.assertEqual(
            sum(int(f["holdMilliseconds"]) for f in frames[:3]),
            harness.SETTLE_MS + harness.WAKE_MS,
        )

    def test_readings_name_pressed_buttons_and_deflected_axes(self) -> None:
        event = state(0, 0, [[6, 0.3], [7, 0.9]], [0.1, -0.8, 0.6, 0])
        self.assertEqual(harness.readings(event), {"b7", "a1-", "a2+"})

    def test_a_clean_run_matches_every_control_on_the_fed_pad(self) -> None:
        for wake in (True, False):
            with self.subTest(wake=wake):
                result = harness.classify(run(10_000, wake=wake), 1_000, 120_000)
                self.assertEqual(
                    result["connected"],
                    {"id": "fed", "mapping": "standard", "nb": 18, "na": 4},
                )
                statuses = {row["status"] for row in result["controls"]}
                self.assertEqual(statuses, {"ok"})
                self.assertEqual(result["rumble"], "complete" if wake else None)

    def test_guide_is_pressed_after_every_other_control(self) -> None:
        names = [control.name for control in harness.CONTROLS]
        self.assertEqual(names[-1], "Guide")

    def test_a_dropped_or_moved_control_is_reported(self) -> None:
        events = run(10_000, wake=True)
        share = next(i for i, c in enumerate(harness.CONTROLS) if c.name == "Share")
        start = 10_000 + share * STEP_MS + 40
        events = [e for e in events if not (start <= e["t"] < start + 2 * STEP_MS)]
        events.append(state(start + STEP_MS + 900, 2, [[0, 1.0]]))
        rows = {
            row["control"]: row
            for row in harness.classify(events, 1_000, 120_000)["controls"]
        }
        self.assertEqual(rows["Share"]["status"], "missing")
        self.assertEqual(rows["Left stick right"]["status"], "differs")
        rows_moved = harness.classify(
            [*run(10_000, wake=True), state(10_040 + 3, 2, [[5, 1.0]])], 1_000, 120_000
        )
        self.assertEqual(rows_moved["controls"][0]["status"], "differs")

    def test_a_press_that_arrives_a_little_early_counts_for_its_own_step(self) -> None:
        events = [
            {**e, "t": e["t"] - 5}
            if e.get("ev") == "state" and e["t"] >= 10_000 + STEP_MS
            else e
            for e in run(10_000, wake=False)
        ]
        statuses = {
            row["status"]
            for row in harness.classify(events, 1_000, 120_000)["controls"]
        }
        self.assertEqual(statuses, {"ok"})

    def test_no_wake_press_reports_no_pad(self) -> None:
        events = [
            e
            for e in run(10_000, wake=False)
            if "b0" not in harness.readings(e) or e.get("ev") != "state"
        ]
        self.assertIsNone(harness.classify(events, 1_000, 120_000)["connected"])


if __name__ == "__main__":
    unittest.main()
