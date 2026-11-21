"""Measures the input pipeline's CPU cost on real hardware and compares two builds.

`measure` runs timed rounds while someone moves a controller's sticks and appends one JSON line
per round to `.build/perf/<label>.jsonl`. `report` turns two labels into a benchstat-style
Markdown comparison: medians with the 95% confidence interval of the median, a two-sided
Mann-Whitney U p-value, and a verdict only where p < 0.05.
"""

from __future__ import annotations

import argparse
import ctypes
import functools
import json
import math
import platform
import plistlib
import subprocess
import sys
import time
import urllib.parse
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from string import Template
from typing import Any, NamedTuple

PROJECT_DIR = Path(__file__).resolve().parents[2]
OUTPUT_ROOT = PROJECT_DIR / ".build" / "perf"
TEMPLATE = Path(__file__).resolve().with_name("perf_report_template.md")
APP = Path("/Applications/OpenJoystickDriver.app")
PROCESS = "OpenJoystickDriver"
# `ojd diagnose --frames` accepts 1-15 seconds.
MAX_ROUND_SECONDS = 15
# A round starts once the controller reports this many frames in one second.
START_FRAMES = 20
WAIT_SECONDS = 300
# A round counts only while input never rests: idle CPU spread over fewer frames would inflate
# the cost per frame. Its frames span all but this much of the round, with no longer pause.
ROUND_SLACK_NS = 1_000_000_000
MAX_PAUSE_NS = 500_000_000
SIGNIFICANCE = 0.05
CONFIDENCE = 0.95

Run = dict[str, Any]


@dataclass(frozen=True)
class Metric:
    """One per-run figure: how to read it from a run and which way is better."""

    key: str
    title: str
    unit: str
    lower_is_better: bool
    digits: int

    def value(self, run: Run) -> float:
        wall = run["wallMs"] / 1000
        cpu = run["userMs"] + run["systemMs"]
        frames = max(run["frames"], 1)
        return {
            "fps": run["frames"] / wall,
            "cpuPercent": cpu / run["wallMs"] * 100,
            "cpuPerFrame": cpu * 1000 / frames,
            "userPerFrame": run["userMs"] * 1000 / frames,
            "systemPerFrame": run["systemMs"] * 1000 / frames,
            "wakeupsPerFrame": run["wakeups"] / frames,
        }[self.key]


METRICS = [
    Metric("cpuPerFrame", "CPU per frame", "µs", True, 1),
    Metric("userPerFrame", "User CPU per frame", "µs", True, 1),
    Metric("systemPerFrame", "System CPU per frame", "µs", True, 1),
    Metric("wakeupsPerFrame", "Idle wakeups per frame", "", True, 2),
    Metric("cpuPercent", "CPU", "%", True, 2),
    Metric("fps", "Frames per second", "fps", False, 0),
]


# MARK: - Process CPU


class _RusageInfoV0(ctypes.Structure):
    _fields_ = [
        ("uuid", ctypes.c_uint8 * 16),
        ("user_time", ctypes.c_uint64),
        ("system_time", ctypes.c_uint64),
        ("pkg_idle_wkups", ctypes.c_uint64),
        ("interrupt_wkups", ctypes.c_uint64),
        ("pageins", ctypes.c_uint64),
        ("wired_size", ctypes.c_uint64),
        ("resident_size", ctypes.c_uint64),
        ("phys_footprint", ctypes.c_uint64),
        ("proc_start_abstime", ctypes.c_uint64),
        ("proc_exit_abstime", ctypes.c_uint64),
    ]


class _Timebase(ctypes.Structure):
    _fields_ = [("numer", ctypes.c_uint32), ("denom", ctypes.c_uint32)]


def process_usage(pid: int) -> tuple[float, float, int]:
    """User CPU ms, system CPU ms and idle and interrupt wakeups of `pid` since it started."""
    libc = ctypes.CDLL("/usr/lib/libSystem.B.dylib")
    info = _RusageInfoV0()
    if libc.proc_pid_rusage(pid, 0, ctypes.byref(info)) != 0:
        raise OSError(f"proc_pid_rusage({pid}) failed")
    timebase = _Timebase()
    libc.mach_timebase_info(ctypes.byref(timebase))
    # The rusage times are in mach absolute time units.
    scale = timebase.numer / timebase.denom / 1e6
    wakeups = info.pkg_idle_wkups + info.interrupt_wkups
    return info.user_time * scale, info.system_time * scale, wakeups


# MARK: - Measuring


def find_pid(name: str) -> int:
    out = subprocess.run(
        ["pgrep", "-x", name], capture_output=True, text=True, check=False
    )
    pids = [int(line) for line in out.stdout.split()]
    if not pids:
        raise SystemExit(f"error: no running process named {name}")
    return pids[0]


class Window(NamedTuple):
    """What the matching controllers read in one `ojd diagnose --frames` window."""

    frames: int
    span_ns: int
    longest_pause_ns: int


def controller_window(seconds: int, controller: str) -> Window:
    """Frames, span and longest pause of controllers whose name contains `controller`."""
    out = subprocess.run(
        ["ojd", "--json", "diagnose", "--frames", str(seconds)],
        capture_output=True,
        text=True,
        check=False,
    )
    try:
        timings = json.loads(out.stdout).get("timings", [])
    except json.JSONDecodeError:
        return Window(0, 0, 0)
    summaries = [t["summary"] for t in timings if controller in t.get("name", "")]
    pauses = [
        g["maxNanoseconds"]
        for s in summaries
        for g in s.get("gaps", [])
        if g["gap"] == "ReadToRead"
    ]
    return Window(
        frames=sum(s["frames"] for s in summaries),
        span_ns=min((s["spanNanoseconds"] for s in summaries), default=0),
        longest_pause_ns=max(pauses, default=0),
    )


def steady(window: Window, seconds: int) -> str | None:
    """Why `window` does not show input for its whole round, or None when it does."""
    if window.frames < START_FRAMES * seconds:
        return f"{window.frames} frames in {seconds} s"
    if window.span_ns < seconds * 1_000_000_000 - ROUND_SLACK_NS:
        return f"input spanned {window.span_ns / 1e9:.1f} of {seconds} s"
    if window.longest_pause_ns > MAX_PAUSE_NS:
        return f"input rested {window.longest_pause_ns / 1e9:.1f} s"
    return None


def environment(controller: str) -> dict[str, str]:
    def run(*args: str) -> str:
        return subprocess.run(
            args, capture_output=True, text=True, check=False
        ).stdout.strip()

    info: dict[str, Any] = {}
    plist = APP / "Contents" / "Info.plist"
    if plist.exists():
        info = plistlib.loads(plist.read_bytes())
    version = info.get("CFBundleShortVersionString", "?")
    build = info.get("CFBundleVersion", "?")
    return {
        "app": f"{version} ({build})",
        # The installed build, not this checkout, is what the rounds measure.
        "commit": str(info.get("OJDSourceCommit", "?"))[:9],
        "macOS": f"{platform.mac_ver()[0]} ({run('sw_vers', '-buildVersion')})",
        "chip": run("sysctl", "-n", "machdep.cpu.brand_string"),
        "controller": controller,
    }


def measure(args: argparse.Namespace) -> None:
    seconds = min(args.seconds, MAX_ROUND_SECONDS)
    pid = find_pid(args.process)
    out = OUTPUT_ROOT / f"{args.label}.jsonl"
    out.parent.mkdir(parents=True, exist_ok=True)
    env = environment(args.controller)
    index = 1
    deadline = time.monotonic() + WAIT_SECONDS
    while index <= args.runs:
        print(
            f"run {index}/{args.runs}: move the sticks of '{args.controller}'...",
            flush=True,
        )
        while controller_window(1, args.controller).frames < START_FRAMES:
            if time.monotonic() > deadline:
                raise SystemExit(
                    "error: no steady controller input within the wait limit"
                )
        user0, system0, wakeups0 = process_usage(pid)
        start = time.monotonic_ns()
        window = controller_window(seconds, args.controller)
        wall_ms = (time.monotonic_ns() - start) / 1e6
        user1, system1, wakeups1 = process_usage(pid)
        frames = window.frames
        if reason := steady(window, seconds):
            print(f"  discarded: {reason}; repeating the round", flush=True)
            continue
        deadline = time.monotonic() + WAIT_SECONDS
        run = {
            "label": args.label,
            "note": args.note,
            "run": index,
            "time": datetime.now(UTC).isoformat(timespec="seconds"),
            "pid": pid,
            "frames": frames,
            "wallMs": round(wall_ms, 1),
            "userMs": round(user1 - user0, 2),
            "systemMs": round(system1 - system0, 2),
            "wakeups": wakeups1 - wakeups0,
            **env,
        }
        with out.open("a") as file:
            file.write(json.dumps(run) + "\n")
        print(
            f"  frames={frames} wall={wall_ms:.0f} ms "
            f"cpu/frame={METRICS[0].value(run):.1f} µs",
            flush=True,
        )
        index += 1
    print(f"wrote {out}")


# MARK: - Statistics


def median(values: list[float]) -> float:
    ordered = sorted(values)
    mid = len(ordered) // 2
    return ordered[mid] if len(ordered) % 2 else (ordered[mid - 1] + ordered[mid]) / 2


def median_interval(values: list[float]) -> tuple[float, float] | None:
    """The distribution-free confidence interval of the median, or None with too few runs.

    The bounds are the order statistics whose binomial coverage reaches ``CONFIDENCE``.
    """
    n = len(values)
    ordered = sorted(values)
    tail = (1 - CONFIDENCE) / 2
    cumulative = 0.0
    k = 0
    while k < n:
        step = math.comb(n, k) / 2**n
        if cumulative + step > tail:
            break
        cumulative += step
        k += 1
    if k == 0:
        return None
    return ordered[k - 1], ordered[n - k]


@functools.cache
def _u_count(n: int, m: int, u: int) -> int:
    """Orderings of n first-sample and m second-sample values in which the first sample wins u
    of the n*m pairs; the largest value either wins all m pairs or none."""
    if u < 0:
        return 0
    if n == 0 or m == 0:
        return 1 if u == 0 else 0
    return _u_count(n - 1, m, u - m) + _u_count(n, m - 1, u)


def mann_whitney_p(a: list[float], b: list[float]) -> float:
    """The two-sided Mann-Whitney U p-value: exact without ties, normal approximation with them."""
    n, m = len(a), len(b)
    if n == 0 or m == 0:
        return 1.0
    pooled = sorted([(v, 0) for v in a] + [(v, 1) for v in b])
    ranks = [0.0] * len(pooled)
    ties: list[int] = []
    i = 0
    while i < len(pooled):
        j = i
        while j + 1 < len(pooled) and pooled[j + 1][0] == pooled[i][0]:
            j += 1
        for k in range(i, j + 1):
            ranks[k] = (i + j) / 2 + 1
        ties.append(j - i + 1)
        i = j + 1
    rank_sum = sum(r for r, (_, group) in zip(ranks, pooled, strict=True) if group == 0)
    u = rank_sum - n * (n + 1) / 2
    if all(t == 1 for t in ties):
        total = math.comb(n + m, n)
        low = int(min(u, n * m - u))
        tail = sum(_u_count(n, m, s) for s in range(low + 1)) / total
        return min(1.0, 2 * tail)
    mean = n * m / 2
    tie_term = sum(t**3 - t for t in ties) / ((n + m) * (n + m - 1))
    variance = n * m / 12 * ((n + m + 1) - tie_term)
    if variance <= 0:
        return 1.0
    z = (abs(u - mean) - 0.5) / math.sqrt(variance)
    return min(1.0, math.erfc(max(z, 0) / math.sqrt(2)))


# MARK: - Report


def load(label: str) -> list[Run]:
    path = OUTPUT_ROOT / f"{label}.jsonl"
    if not path.exists():
        raise SystemExit(
            f"error: no runs at {path}; run `just perf-measure {label}` first"
        )
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def number(value: float, digits: int) -> str:
    return f"{value:,.{digits}f}".replace("-", "−")


def cell(values: list[float], metric: Metric) -> str:
    mid = median(values)
    interval = median_interval(values)
    spread = "± ∞"
    if interval and mid:
        spread = f"± {max(interval[1] - mid, mid - interval[0]) / abs(mid) * 100:.0f}%"
    unit = f" {metric.unit}" if metric.unit and metric.unit != "%" else metric.unit
    return f"{number(mid, metric.digits)}{unit} {spread}"


def compare_row(base: list[Run], candidate: list[Run], metric: Metric) -> str:
    a = [metric.value(r) for r in base]
    b = [metric.value(r) for r in candidate]
    old, new = median(a), median(b)
    delta = new - old
    percent = delta / old * 100 if old else 0.0
    p = mann_whitney_p(a, b)
    if p >= SIGNIFICANCE:
        verdict = "~"
    elif (delta < 0) == metric.lower_is_better:
        verdict = "🟢 better"
    else:
        verdict = "🔴 worse"
    sign = "+" if delta >= 0 else ""
    delta_text = f"{sign}{number(delta, metric.digits)}"
    if metric.unit == "%":
        delta_text += " pp"
    elif metric.unit:
        delta_text += f" {metric.unit}"
    return (
        f"| {metric.title} | {cell(a, metric)} | {cell(b, metric)} | {delta_text} "
        f"| {sign}{number(percent, 1)}% | p={p:.3f} n={len(a)}+{len(b)} | {verdict} |"
    )


def chart_url(
    base_label: str, candidate_label: str, base: list[Run], candidate: list[Run]
) -> str:
    keys = ["cpuPerFrame", "userPerFrame", "systemPerFrame"]
    chosen = [m for m in METRICS if m.key in keys]

    def series(runs: list[Run]) -> list[float]:
        return [round(median([m.value(r) for r in runs]), 1) for m in chosen]

    config = {
        "type": "bar",
        "data": {
            "labels": [m.title.replace("µs", "us") for m in chosen],
            "datasets": [
                {"label": base_label, "data": series(base)},
                {"label": candidate_label, "data": series(candidate)},
            ],
        },
        "options": {
            "plugins": {
                "title": {
                    "display": True,
                    "text": "Median CPU us per frame (lower is better)",
                }
            },
            "scales": {"y": {"beginAtZero": True}},
        },
    }
    query = urllib.parse.urlencode(
        {
            "v": "4",
            "w": "600",
            "h": "300",
            "bkg": "white",
            "devicePixelRatio": "1",
            "c": json.dumps(config, separators=(",", ":")),
        },
        quote_via=urllib.parse.quote,
    )
    return f"https://quickchart.io/chart?{query}"


def raw_rows(runs: list[Run]) -> list[str]:
    rows = []
    for run in runs:
        rows.append(
            f"| {run['label']} | {run['run']} | {run.get('note') or '—'} | {run['frames']} "
            f"| {number(run['wallMs'], 0)} | {number(run['userMs'], 0)} "
            f"| {number(run['systemMs'], 0)} | {run['wakeups']} "
            f"| {number(METRICS[0].value(run), 1)} |"
        )
    return rows


def environment_rows(base: list[Run], candidate: list[Run]) -> list[str]:
    rows = []
    for key in ["app", "commit", "macOS", "chip", "controller"]:
        old = base[-1].get(key, "?")
        new = candidate[-1].get(key, "?")
        rows.append(f"| {key} | {old} | {new} |")
    notes = (
        {r.get("note") or "—" for r in base},
        {r.get("note") or "—" for r in candidate},
    )
    rows.append(
        f"| note | {', '.join(sorted(notes[0]))} | {', '.join(sorted(notes[1]))} |"
    )
    return rows


def table(header: list[str], align: str, rows: list[str]) -> str:
    """A GitHub table in markdownlint's compact style; `align` holds `l`, `r` or `c` per column."""
    rule = {"l": ":--", "r": "--:", "c": ":-:"}
    lines = [
        "| " + " | ".join(header) + " |",
        "| " + " | ".join(rule[a] for a in align) + " |",
    ]
    return "\n".join(lines + rows)


def render(
    base_label: str, candidate_label: str, base: list[Run], candidate: list[Run]
) -> str:
    # The template holds whole tables as placeholders so it stays valid Markdown itself.
    labels = [base_label, candidate_label]
    return Template(TEMPLATE.read_text()).substitute(
        base=base_label,
        candidate=candidate_label,
        environment=table(["Field", *labels], "lll", environment_rows(base, candidate)),
        results=table(
            ["Metric", *labels, "Δ", "Δ %", "Test", "Verdict"],
            "lrrrrlc",
            [compare_row(base, candidate, m) for m in METRICS],
        ),
        chart=chart_url(base_label, candidate_label, base, candidate),
        raw=table(
            [
                "Label",
                "Run",
                "Note",
                "Frames",
                "Wall ms",
                "User ms",
                "System ms",
                "Idle wakeups",
                "CPU µs/frame",
            ],
            "lrlrrrrrr",
            raw_rows(base) + raw_rows(candidate),
        ),
    )


def report(args: argparse.Namespace) -> None:
    text = render(args.base, args.candidate, load(args.base), load(args.candidate))
    if args.output:
        Path(args.output).write_text(text)
        print(f"wrote {args.output}")
    else:
        sys.stdout.write(text)


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)
    m = commands.add_parser(
        "measure", help="Record timed rounds while the sticks move."
    )
    m.add_argument(
        "label", help="Name of the run set, such as a commit and window state."
    )
    m.add_argument(
        "--runs", type=int, default=10, help="Rounds to record (default: 10)."
    )
    m.add_argument(
        "--seconds", type=int, default=MAX_ROUND_SECONDS, help="Seconds per round."
    )
    m.add_argument(
        "--controller", default="", help="Part of the controller name to count."
    )
    m.add_argument("--note", default="", help="Conditions, such as 'window closed'.")
    m.add_argument("--process", default=PROCESS, help="Process to measure.")
    m.set_defaults(func=measure)
    r = commands.add_parser("report", help="Compare two run sets as Markdown.")
    r.add_argument("base")
    r.add_argument("candidate")
    r.add_argument(
        "--output", help="Write the Markdown to this file instead of stdout."
    )
    r.set_defaults(func=report)
    args = parser.parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
