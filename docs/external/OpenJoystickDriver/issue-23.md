# #23: 0.5.0-alpha.4 leaks around 103 MB/h while idle. Fixed on main, please cut a release

> External GitHub snapshot. GitHub is authoritative if this file is stale.

- **Repository:** `xsyetopz/OpenJoystickDriver`
- **Source:** https://github.com/xsyetopz/OpenJoystickDriver/issues/23
- **State:** OPEN
- **Author:** fabio-dee
- **Created:** 2026-08-02T13:39:05Z
- **Updated:** 2026-08-25T16:20:55Z
- **Closed:** —
- **Labels:** bug, help wanted

## Report

## Summary

With no controller connected and no consumer app running, `OpenJoystickDriverDaemon` grew to 2586 MB of physical footprint over roughly 25 hours of idle uptime. Growth was monotonic, and `phys_footprint_peak` matched `phys_footprint` at every check.

I then built `main` at `559933f` and repeated the measurement. Idle growth fell from roughly 103 MB/h to 0.22 MB/h, so the defect appears to be already fixed in current code.

I am filing this as a release request rather than a defect report. The fix has been on `main` for several weeks, the published release still carries the leak, and I could find no commit message, CHANGELOG entry, or issue that records the fix happening.

## Environment

- OpenJoystickDriver **0.5.0-alpha.4**, installed from the GitHub release `.app`
- macOS 15.7.8 Sequoia (24G824), Apple Silicon
- Comparison build: `main` @ `559933f`, compiled with the documented `swift build` path
- Input Monitoring: granted
- No controller connected at any point during either measurement
- Daemon started at login through the bundled `com.openjoystickdriver.daemon` LaunchAgent (`RunAtLoad=1`, `KeepAlive=1`)

## Evidence: 0.5.0-alpha.4

### Memory

`footprint -p <pid>` after roughly 25 hours idle:

```
OpenJoystickDriverDaemon [859]: 64-bit   Footprint: 2586 MB

  Dirty      Clean  Reclaimable  Regions   Category
1920 MB        0 B          0 B       13   MALLOC_NANO
 607 MB        0 B        32 KB     6799   MALLOC_TINY
  47 MB        0 B      2912 KB        5   MALLOC_MEDIUM

    phys_footprint:      2586 MB
    phys_footprint_peak: 2586 MB
```

1920 MB of `MALLOC_NANO` spread across only 13 regions points to a very large count of small, long-lived allocations. A cache of that size would normally show reclaimable pages. This one shows none.

### Log

`/tmp/com.openjoystickdriver.daemon.out` reached 3.8 MB and 65,117 lines over the same window. Normalised by frequency:

```
64,814 ×  [DextOutputDispatcher] IOHIDManagerOpen warning: -1ffffd39
   282 ×  [ForegroundConsumerOutputMonitor] Output active
           (no consumer apps holding OJD virtual device)
     1 ×  [XPCService] Listening on com.openjoystickdriver.xpc
     1 ×  [PermissionManager] Input Monitoring state changed: unknown -> granted
     1 ×  [DeviceManager] Started - dual detection active
```

`-1ffffd39` is the negated form of `0xE00002C7`. `IOKit/IOReturn.h` defines that value as:

```c
#define kIOReturnUnsupported  iokit_common_err(0x2c7)  // unsupported function
```

### Correlation

```
64,814 attempts / 25 h        = around 43 open attempts per minute, sustained
1920 MB MALLOC_NANO / 64,814  = around 30 KB retained per attempt
2586 MB / 25 h                = around 103 MB per hour
```

The shape is an unbounded retry against an error that will not resolve on its own, retaining an allocation on each pass. `DextOutputDispatcher` and the `ForegroundConsumerOutputMonitor` of that build were both on this code path, so I cannot attribute the retained memory to one of them from outside the process.

## Evidence: main @ 559933f

Thirty minutes idle, no controller connected, sampled every 60 seconds.

| | 0.5.0-alpha.4 | main @ 559933f |
|---|---|---|
| Idle footprint growth | around 103 MB/h | 0.22 MB/h |
| Absolute change | 2586 MB over 25 h | +110 KB over 30 min (7.359 → 7.469 MB) |
| `MALLOC_NANO` dirty | 1920 MB | 2.72 MB |
| `MALLOC_TINY` dirty | 607 MB | 0.47 MB |
| Failed HID open attempts | around 43/min, sustained | 7 total, all within 14 ms of startup |

The `main` curve rises in discrete steps and then holds flat. Twenty-four of 31 samples show no change from the preceding sample, and four steps of 15 to 32 KB account for the entire delta. Total growth of 110 KB against 16 KB page granularity sits close to the measurement floor, which reads as lazy initialisation settling rather than accumulation.

At OS level (`log show`, `com.apple.iohid` subsystem) `main` produced 7 × `IOServiceOpen failed: 0xe00002c7` inside a 14 ms window at startup, then produced none for the remaining thirty minutes. The failure is the same `kIOReturnUnsupported` as before. Current code stops retrying it.

Reading the history, `98b7b0e` looks like the change that mattered, since it caches a single `IOHIDManager` for the process lifetime instead of creating one per poll tick. `d5ce8a6` then removed `DextOutputDispatcher` entirely. Both read to me as side effects of larger refactors rather than targeted fixes. Correct me if I have misread them.

## What this means in practice

Anyone who installs the published release and leaves the login item enabled loses multiple GB of RAM per day without a controller ever being attached. I play a few times a week, so on my machine the daemon sat idle almost all of the time and leaked the whole while.

The second log line reads differently next to the first. `ForegroundConsumerOutputMonitor` already detected that no consumer app held the virtual device, 282 times. The retry loop kept running regardless.

## Suggested directions

1. **Cut a release.** The last one is dated 2026-06-10. Every user installing from the releases page today still gets the leaking build, and no user has a way to discover that current code fixes it.

2. **Record it in the CHANGELOG.** If the fix was incidental, it is worth writing down, so a future refactor does not quietly undo it.

3. **Add an idle footprint regression test.** `swift test` on `main` runs 576 tests across 92 suites and all of them pass. None would have caught a 100 MB/h idle leak. Running the service idle for N seconds and asserting that `phys_footprint` growth stays under a threshold would have.

4. **Bound the remaining retry.** `ForegroundConsumerOutputMonitor.withOpenManager` never sets `isOpen` on failure, so it calls `IOHIDManagerOpen` again on every poll tick with no backoff and no cap. Caching the manager removed the memory cost, so this is low priority now. It is still the same shape that produced the original leak, and `Runtime.swift:187-223` already implements the backoff pattern it needs.

## Caveat

My `main` measurement used an unsigned ad-hoc `.build/debug` binary, which logs `Compatibility virtual gamepad unavailable: Missing entitlement: com.apple.developer.hid.virtual.device`. A signed, installed build may exercise this path differently, so treat those numbers as strong but not conclusive. The 0.5.0-alpha.4 figures come from the shipped signed release and carry no such caveat.

I can re-run the soak against a signed build, capture `malloc_history` or `leaks` output, or test a release candidate before it ships. The reproduction was stable on my side.

## Comments

### xsyetopz — 2026-08-02T16:47:10Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/23#issuecomment-5159340076)

What the actual f#ck!? How did *this* go past me? I do recall having a 5GB memory consumption issue on the old Daemon-based solution which I thought I fixed back then, but apparently *NOT*. Yeah, I think this starts calling for a release more than soon. Holy f#ck.

Enough f#cking stalling. WE NEED A RELEASE SOONER THAN EVER--*EEEEVEN* if we don't have full confirmed supports.

### fabio-dee — 2026-08-03T11:24:06Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/23#issuecomment-5165696123)

No worries @xsyetopz, sh1t happens to everyone!
I would help, but I have no spare time these days.
cheers!

### xsyetopz — 2026-08-07T01:21:20Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/23#issuecomment-5210887848)

Well, It's taking a while when I have other things to do...

*Damn*.

### xsyetopz — 2026-08-09T05:23:53Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/23#issuecomment-5229937582)

I updated README.md to let users know I wiped all previous, heavily leaky releases off the publication, so that `0.5.0-beta.1` could take its time to resolve the remaining small issues, and a GUI redoing, before landing.

### xsyetopz — 2026-08-10T09:13:54Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/23#issuecomment-5238196810)

<img width="1072" height="784" alt="Image" src="https://github.com/user-attachments/assets/ef1b2826-49f7-4f60-8bc7-81f6bf9a7382" />

Little bit of early WIP.

### xsyetopz — 2026-08-10T21:38:16Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/23#issuecomment-5246335327)

<img width="872" height="590" alt="Image" src="https://github.com/user-attachments/assets/87d8ae0e-172e-4d86-ac11-88fc6a11a045" />

This will become a sidebar variant just like Profiles tab.

### xsyetopz — 2026-08-11T02:58:47Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/23#issuecomment-5248487519)

> <img alt="Image" width="872" height="590" src="https://private-user-images.githubusercontent.com/187086553/633964016-87d8ae0e-172e-4d86-ac11-88fc6a11a045.png">
> This will become a sidebar variant just like Profiles tab.

<img width="915" height="629" alt="Image" src="https://github.com/user-attachments/assets/9b837fcb-51c5-491f-979c-eddab0e79c0b" />

something like this is a good start. I like it better this way.

### xsyetopz — 2026-08-25T16:20:55Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/23#issuecomment-5413397241)

Try [0.5.0-beta.1](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-beta.1) and tell me if it works!
