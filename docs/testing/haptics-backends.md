# Probe macOS Haptics Backends

Run one route at a time (backend inventory, GameController haptics, SDL output, direct rumble). Record physical behavior before changing identities:

```bash
just diagnose-backends --seconds 5
just diagnose-gamecontroller --seconds 5 --rumble
just diagnose-sdl3 --seconds 5 --rumble
just diagnose-rumble-motors 13623 4112
```

The last example uses the GameSir G7 SE decimal VID/PID; substitute yours, decimal or `0x` hexadecimal. The script drives `ojd controller rumble` with a `VVVV:PPPP` selector, one `sendControllerOutput` command per step, and waits out each bounded rumble (the app ends it) before its explicit stop.

The SDL route can exercise OJD's first-party Microsoft Xbox 360 Wired (045E:028E) with the Xbox 360 HIDAPI descriptor/report format, published through `IOHIDUserDevice` on every supported macOS. The probe changes identities with the installed OJD CLI, matching the running app's service protocol.

An isolated probe tested Apple's legacy Force Feedback API; OJD has no such route, so the observations below are evidence only. A nonzero HID output-report size is a raw-report candidate, not proof of either.

Application rumble on a virtual gamepad reaches the physical controller as one command: a bounded set-rumble (main motors mirrored onto Steam Controller trackpad haptics) or a stop-rumble. A stop writes once; an active remapping rumble claim keeps running. Other consumer reports, such as a DualSense lightbar, drive no physical output.

The GameController diagnostic checks the public controller and haptics path. An `IOHIDUserDevice` creates no public `GCController.haptics` engine.

## GameSir G7 SE Observations

September 2, 2026: four physical GIP output channels isolated with:

```bash
just diagnose-rumble-motors 0x3537 0x1010 200 750
```

The GameSir G7 SE gave a one-to-one actuator map:

| Logical channel | Physical observation |
| --- | --- |
| `LowFrequency` | Left grip motor |
| `HighFrequency` | Right grip motor |
| `LeftTrigger` | Left trigger motor |
| `RightTrigger` | Right trigger motor |

Each step stopped all four channels before and after its bounded pulse. This verifies independent addressing of four motors through OJD's raw-USB GIP output, not that every virtual consumer supplies four values.

August 25, 2026, GameSir G7 SE (3537:1010) on OJD's raw USB GIP transport:

| Route | Framework evidence | Physical observation |
| --- | --- | --- |
| SDL 1BAD:F901 baseline | The virtual descriptor exposes an output report, but a dedicated PCSX2 run produced no OJD virtual-output callback; the app logged virtual-gamepad creation only. Earlier output-report lines came from an Xbox 360 identity run | Input works. Normal rumble is missing; only a rare, faint pulse under a second, no SDL-to-OJD rumble path, possibly from another consumer. |
| Apple Force Feedback/PID | `FFIsForceFeedback` returned `0x80000003`; no Force Feedback device opened | No rumble. With OJD quit, no controller HID service was exposed to test. |
| Apple GameController | `apple-gamecontroller` selected, but `GCController.controllers()` returned none and no public haptics engine existed | LED stayed on; input was not available during the observation. No haptic pulse could be submitted. |
| Exact ASTRO SDL HIDAPI Xbox 360 | The `sdl2-3` profile published 9886:0024 and exposed its eight-byte output report | Input and physical rumble worked. |
| Microsoft Xbox One S Bluetooth revision 1 | Probe published 045E:02E0 with Bluetooth transport and the matching descriptor | LED and application discovery worked, but input did not; rumble was unavailable. |
| Microsoft Xbox One S Bluetooth revision 2 | Probe published 045E:02FD with Bluetooth transport and the matching descriptor | LED and application discovery worked, but input did not; rumble was unavailable. |
| Xbox One HID experiment | Probe and identity experiments published 045E:02EA / 045E:02FD Bluetooth-shaped HID tuples | LED and discovery sometimes worked, but usable input and rumble did not. Evidence only; OJD has no route for it. |
| Controller LED | Reflects the physical GIP session, not a haptics backend | On while OJD owned the controller, off after OJD quit. |

Results apply to this controller, OS, consumer, and OJD build. Exact HIDAPI-compatible reports are the working cross-application path here; that does not show every application accepts the spoofed identity, or that PID and GameController haptics fail on every real controller.

OJD cancels a superseded delayed stop before scheduling a replacement, so an earlier request cannot silence a later rumble after 250 milliseconds. Scheduling does not make an application emit reports for an identity lacking its output protocol. Evidence, not OJD identities: the `sdl2-3` identity with its ASTRO 9886:0024 probe, the input-only GameStop identity, the `x360-hid` selection, and the two failed Microsoft Bluetooth probe variants. OJD publishes only `SDLCompatible` or `Generic`.
