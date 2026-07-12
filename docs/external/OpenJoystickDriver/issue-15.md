# #15: Logitech F310 (X mode): no input on macOS 26 — profile declares wrong OUT endpoint (1 -> hardware uses 2)

> External GitHub snapshot. GitHub is authoritative if this file is stale.

- **Repository:** `xsyetopz/OpenJoystickDriver`
- **Source:** https://github.com/xsyetopz/OpenJoystickDriver/issues/15
- **State:** CLOSED
- **Author:** tsanva
- **Created:** 2026-07-11T09:02:36Z
- **Updated:** 2026-07-12T05:47:35Z
- **Closed:** 2026-07-12T05:47:35Z
- **Labels:** bug, good first issue

## Report

## Environment

- OpenJoystickDriver 0.5.0-alpha.4 (release DMG)
- macOS 26.5.2 (Tahoe), Apple Silicon (M1)
- Logitech F310, switch on X -> enumerates as `046d:c21d` ("Gamepad F310", class 255/93/1)

## Symptom

No input at all on this setup — different from #11, where input flowed but was mis-mapped:

- The daemon detects the controller and takes exclusive ownership (`UsbExclusiveOwner = OpenJoystickDriverDaemon` in `ioreg`).
- Two "OpenJoystickDriver Virtual Gamepad" devices are created (visible in `hidutil list`).
- Input Monitoring is granted; unified log shows **no** `TCC deny IOHIDDeviceOpen` after a daemon restart.
- Input Test shows nothing; browsers never see the virtual pad (expected, since it never emits).

## Verified hardware fact: the F310 profile's OUT endpoint is wrong

`Resources/Controllers/logitech-gamepad-f310.json` declares:

```json
"endpoints": { "in": 129, "out": 1 }
```

But the hardware's only configuration is:

```
interface 0 alt 0: class=ff sub=5d proto=01 endpoints=2
  ep 0x81  attr=03 (interrupt)  maxpkt=32  interval=4
  ep 0x02  attr=03 (interrupt)  maxpkt=32  interval=8
```

The OUT endpoint is **0x02**, not 0x01 (unlike a genuine wired 360 pad). Writes to 0x01 fail — verified with libusb:

```
claim_interface(0): Success
LED write to 0x01: Entity not found (LIBUSB_ERROR_NOT_FOUND)
```

Writing the same wired-360 LED packet (`01 03 02`) to **0x02** succeeds. So at minimum, all startup/LED/rumble writes for this device go nowhere. Suggested fix: `"out": 2` in the profile.

## Input itself needs no activation (works in an independent reader)

On this same machine and session, a minimal libusb C reader — `set_configuration(1)`, `claim_interface(0)`, interrupt reads on `0x81` — receives the standard 20-byte wired-360 input reports immediately and reliably (buttons, dpad, analog triggers, sticks all correct). No activation packet is required; the controller streams as soon as the interface is claimed and read. So the physical device and macOS 26's USB stack are fine, which suggests the daemon's read pipeline is stalling somewhere on macOS 26 even before the endpoint issue matters for input.

One possibly-relevant log line from the daemon right after startup:

```
[com.apple.iohid:default] Device is seized, reports will be dropped until the seizing client closes
```

## Aside (minor UX)

If Input Monitoring is granted while the LoginItem daemon is already running, the daemon keeps its cached TCC denial until manually restarted — the menu-bar "Request access" button appears to do nothing. Restarting only the menu-bar app doesn't help since the daemon survives. Might be worth having the button restart the daemon.

Happy to test fixes/alphas on macOS 26 — I have the device and a libusb test harness ready.

## Comments

_No comments._
