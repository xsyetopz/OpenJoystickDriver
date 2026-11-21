from __future__ import annotations

import math
import unittest

from Scripts.Diagnostics import perf


def run(
    label: str, index: int, frames: int, user_ms: float, system_ms: float
) -> perf.Run:
    return {
        "label": label,
        "run": index,
        "note": "window closed",
        "frames": frames,
        "wallMs": 15_000.0,
        "userMs": user_ms,
        "systemMs": system_ms,
        "wakeups": frames * 2,
        "app": "0.6.0",
        "commit": label,
        "macOS": "27.2",
        "chip": "test",
        "controller": "2C",
    }


class MannWhitneyTests(unittest.TestCase):
    def test_separated_samples_give_the_exact_two_sided_p(self) -> None:
        p = perf.mann_whitney_p([1, 2, 3, 4, 5], [6, 7, 8, 9, 10])
        self.assertAlmostEqual(p, 2 / math.comb(10, 5))

    def test_identical_samples_are_not_significant(self) -> None:
        self.assertEqual(perf.mann_whitney_p([5.0] * 6, [5.0] * 6), 1.0)

    def test_three_runs_each_can_never_reach_significance(self) -> None:
        self.assertGreaterEqual(
            perf.mann_whitney_p([1, 2, 3], [4, 5, 6]), perf.SIGNIFICANCE
        )


class MedianIntervalTests(unittest.TestCase):
    def test_ten_runs_bound_the_median_by_the_second_and_ninth_values(self) -> None:
        self.assertEqual(
            perf.median_interval([float(v) for v in range(1, 11)]), (2.0, 9.0)
        )

    def test_five_runs_are_too_few_for_a_95_percent_interval(self) -> None:
        self.assertIsNone(perf.median_interval([1.0, 2.0, 3.0, 4.0, 5.0]))


class ReportTests(unittest.TestCase):
    def test_lower_cpu_per_frame_is_marked_better_with_its_delta(self) -> None:
        base = [run("old", i, 6_000, 2_400 + i, 1_800) for i in range(10)]
        candidate = [run("new", i, 6_000, 1_200 + i, 900) for i in range(10)]
        metric = next(m for m in perf.METRICS if m.key == "cpuPerFrame")

        row = perf.compare_row(base, candidate, metric)

        self.assertIn("🟢 better", row)
        self.assertIn("−49.9%", row)
        self.assertIn("n=10+10", row)

    def test_report_fills_every_template_field(self) -> None:
        base = [run("old", i, 6_000, 2_400 + i, 1_800) for i in range(10)]
        candidate = [run("new", i, 6_000, 1_200 + i, 900) for i in range(10)]

        text = perf.render("old", "new", base, candidate)

        self.assertNotIn("$", text)
        self.assertIn("https://quickchart.io/chart?v=4", text)
        raw = [line for line in text.splitlines() if line.startswith("| old | ")]
        self.assertEqual(len(raw), 10)


if __name__ == "__main__":
    unittest.main()
