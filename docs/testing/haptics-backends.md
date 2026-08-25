# Probe macOS haptics backends

Use the isolated package under `tools/haptics-backend-probe` to distinguish
three different output routes. Run one route at a time and record physical
behavior before changing identities:

```bash
swift build --package-path tools/haptics-backend-probe
swift run --package-path tools/haptics-backend-probe HapticsBackendProbe try force-feedback
swift run --package-path tools/haptics-backend-probe HapticsBackendProbe try gamecontroller --pulse
swift run --package-path tools/haptics-backend-probe HapticsBackendProbe try xbox-one-hid
swift run --package-path tools/haptics-backend-probe HapticsBackendProbe try sdl2-3
```

The `sdl2-3` route changes OJD to the exact ASTRO `9886:0024` Xbox 360 HIDAPI
descriptor/report identity. OJD publishes it through CoreHID on macOS 15 and later and through
`IOHIDUserDevice` on macOS 10.15 through 14. The probe uses the installed OJD
CLI to change identities so its application-service protocol always matches
the running installed app.

The Force Feedback route is different. Apple's legacy Force Feedback API takes
an IOKit HID service and reports whether that service implements its PID-style
interface. A nonzero HID output-report size is only a raw-report candidate; it
does not imply Force Feedback compatibility or physical rumble.

The GameController route changes OJD to `apple-gamecontroller`, waits for the
virtual HID replacement, and checks for a public `GCController.haptics` engine.
CoreHID virtual-device access alone does not synthesize that engine.

## GameSir G7 SE observations

The following observations were recorded on August 25, 2026 for the connected
GameSir G7 SE (`3537:1010`) using OJD's raw USB GIP transport:

| Route | Framework evidence | Physical observation |
| --- | --- | --- |
| SDL `1BAD:F901` baseline | The virtual descriptor exposes an output report, but a dedicated PCSX2 run produced no OJD virtual-output callback | Input works. Normal rumble is missing; only a rare, faint pulse lasting less than a second was observed. |
| Apple Force Feedback/PID | `FFIsForceFeedback` returned `0x80000003`; no Force Feedback device opened | No rumble. With OJD quit, no controller HID service was exposed to test. |
| Apple GameController | `apple-gamecontroller` selected, but `GCController.controllers()` returned none and no public haptics engine existed | LED stayed on; input was not available during the observation. No haptic pulse could be submitted. |
| Exact ASTRO SDL HIDAPI Xbox 360 | The `sdl2-3` profile published `9886:0024` and exposed its eight-byte output report | Input and physical rumble worked. |
| Microsoft Xbox One S Bluetooth revision 1 | Probe published `045E:02E0` with Bluetooth transport and the matching descriptor | LED and application discovery worked, but input did not; rumble was unavailable. |
| Microsoft Xbox One S Bluetooth revision 2 | Probe published `045E:02FD` with Bluetooth transport and the matching descriptor | LED and application discovery worked, but input did not; rumble was unavailable. |
| Xbox One HID | `xone-hid` selected as `045E:02EA`; the virtual device exposed output report 3 | LED stayed on and PCSX2 Nightly no longer crashed, but input and rumble did not work. |

These results apply to this controller, OS, consumer, and OJD build. They show
that exact HIDAPI-compatible reports are the working cross-application path for
this setup. They do not establish that every application accepts the spoofed
identity or that PID and GameController haptics are unavailable for every real
controller.

The controller LED reflects the physical GIP session rather than proof of a
haptics backend. It remained on while OJD owned the controller and went off
after OJD was quit and the session ended.

In a dedicated SDL `1BAD:F901` run, the installed OJD app logged virtual-device
creation but no virtual-output callback. The physical report above therefore
does not establish an SDL-to-OJD rumble path; the rare pulse may come from
another consumer path and must not be treated as successful rumble. Earlier
output-report lines were captured during an Xbox 360 identity run and do not
apply to the SDL identity.

Separately, OJD now cancels a superseded delayed stop before scheduling a
replacement command, so an older accepted request cannot silence a newer
rumble request after 250 milliseconds. That scheduling hardening does not make
an application emit reports for an identity whose output protocol it does not
support. The verified ASTRO implementation is now the canonical `sdl2-3`
route. The input-only GameStop implementation, the redundant `x360-hid`
selection, and the two failed Microsoft Bluetooth probe variants were removed
from live code; these observations remain as historical evidence.
