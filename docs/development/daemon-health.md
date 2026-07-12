# Daemon runtime health

OpenJoystickDriver includes a bounded daemon soak diagnostic:

```bash
./.build/debug/OpenJoystickDriver --headless diagnose runtime \
  --seconds 300 \
  --interval-ms 1000 \
  --rss-limit-mib 0 \
  --footprint-limit-mib 512
```

Use `--json` for support reports or automation. The MenuBar advanced view exposes the same duration, interval, RSS limit, footprint limit, run, and stop controls.

## What is measured

- resident set size (RSS)
- physical footprint, including dirty/compressed allocator pages
- linear RSS and footprint growth rates
- average process CPU
- file descriptor count and growth
- thread count and growth
- configurable high-water limits

A window shorter than 60 seconds is reported as `insufficientData` unless a high-water limit is already exceeded. A stable bounded run is evidence for that workload, not proof that every execution path is leak-free.

## Foreground-consumer polling leak

On 2026-07-12, the installed daemon had been running for ten days from a 2026-06-10 binary. Local evidence showed:

- approximately 158 MiB RSS
- approximately 9.6 GiB physical footprint
- approximately 9.3 GiB of dirty `MALLOC_SMALL` regions
- repeated GamePolicy `GPProcessMonitor` graphs rooted in IOHIDLib

The foreground-consumer monitor created and opened a new `IOHIDManager` for every one-second scan. Closing and releasing the manager did not reclaim all framework-owned GamePolicy monitor state. An autorelease pool reduced temporary objects but did not fix that ownership behavior.

The production scan now reuses one locked, process-lifetime `IOHIDManager`. It still refreshes `IOHIDManagerCopyDevices` on every scan, so device discovery remains current without constructing another manager.

## Isolated regression probe

The daemon binary has a non-service probe mode. It does not start XPC, USB input, virtual output, or the periodic monitor:

```bash
.build/debug/OpenJoystickDriverDaemon \
  --probe-foreground-consumer-memory=1000
```

Observed on the affected system:

- Before manager reuse, 500 scans added 5,111,808 bytes of physical footprint. No leak-tool result was captured for that run.
- Before manager reuse, 50 scans with stack logging added 901,120 bytes and reported 1,824 leaks totaling 168,752 bytes.
- After manager reuse, 1,000 scans added 278,528 bytes and produced a stable trend.
- After manager reuse, 50 scans with stack logging stayed near 5.8 MiB total and reported 20 leaks totaling 1,616 bytes.

The remaining small IOHIDLib/GamePolicy graphs are process-lifetime state created when the single manager opens; they no longer scale with scan count.

## Required installed-daemon check

The isolated probe proves the repeated-construction path is bounded in the current binary. It does not prove the already running installed daemon changed: that process still contains the older code and must be replaced/restarted before a long active-controller soak can verify the production lifecycle.

Replacing or restarting the installed helper is an external system change and is intentionally not performed by automated validation without confirmation.
