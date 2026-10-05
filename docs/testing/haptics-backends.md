# Probe macOS Haptics Backends

Use the supported diagnostics routes to distinguish backend inventory, GameController haptics, SDL output, and direct physical rumble. Run one route at a time and record physical behavior before changing identities:

```bash
./Scripts/ojd diagnose backends --seconds 5
./Scripts/ojd diagnose gamecontroller --seconds 5 --rumble
./Scripts/ojd diagnose sdl3 --seconds 5 --rumble
./Scripts/ojd diagnose rumble-motors 13623 4112
```

The final example uses the GameSir G7 SE decimal VID/PID; substitute the vendor and product IDs of the connected device, in decimal or `0x` hexadecimal. It drives `ojd controller rumble` with a `VVVV:PPPP` selector built from them, which sends one `sendControllerOutput` command per step; the app ends each bounded rumble itself, so the script waits out the duration before its explicit stop. The SDL route can exercise OJD's first-party Microsoft Xbox 360 Wired `045E:028E` with the Xbox 360 HIDAPI descriptor/report format. OJD publishes it through `IOHIDUserDevice` on every supported macOS. The probe uses the installed OJD CLI to change identities so its application-service protocol always matches the running installed app.

The retired isolated probe also tested Apple's legacy Force Feedback API. Its dated observations remain below as evidence, but that unsupported executable is no longer a live route. A nonzero HID output-report size is only a raw-report candidate; it does not imply Force Feedback compatibility or physical rumble.

Rumble that an application writes to a virtual controller reaches the physical controller as one output command: a bounded set-rumble, with the main motors mirrored onto the Steam Controller trackpad haptics, or a stop-rumble. A stop writes the physical controller once, and an active remapping rumble claim keeps running through it. Other consumer reports, such as a DualSense lightbar, do not drive physical output.

The GameController diagnostic checks the supported public controller and haptics path. `IOHIDUserDevice` publication alone does not synthesize a public `GCController.haptics` engine.

## GameSir G7 SE Observations

On September 2, 2026, the four physical GIP output channels were isolated with:

```bash
just diagnose-rumble-motors 0x3537 0x1010 200 750
```

The connected GameSir G7 SE produced this one-to-one actuator map:

| Logical channel | Physical observation |
| --- | --- |
| `leftMain` | Left grip motor |
| `rightMain` | Right grip motor |
| `leftTrigger` | Left trigger motor |
| `rightTrigger` | Right trigger motor |

Every step explicitly stopped all four channels before and after its bounded pulse. This verifies independent addressing of all four motors through OJD's physical raw-USB GIP output path. It does not imply that every virtual consumer or API supplies four independent motor values.

August 25, 2026 observations for the connected GameSir G7 SE (`3537:1010`) using OJD's raw USB GIP transport:

| Route | Framework evidence | Physical observation |
| --- | --- | --- |
| SDL `1BAD:F901` baseline | The virtual descriptor exposes an output report, but a dedicated PCSX2 run produced no OJD virtual-output callback | Input works. Normal rumble is missing; only a rare, faint pulse lasting less than a second was observed. |
| Apple Force Feedback/PID | `FFIsForceFeedback` returned `0x80000003`; no Force Feedback device opened | No rumble. With OJD quit, no controller HID service was exposed to test. |
| Apple GameController | `apple-gamecontroller` selected, but `GCController.controllers()` returned none and no public haptics engine existed | LED stayed on; input was not available during the observation. No haptic pulse could be submitted. |
| Exact ASTRO SDL HIDAPI Xbox 360 | The `sdl2-3` profile published `9886:0024` and exposed its eight-byte output report | Input and physical rumble worked. |
| Microsoft Xbox One S Bluetooth revision 1 | Probe published `045E:02E0` with Bluetooth transport and the matching descriptor | LED and application discovery worked, but input did not; rumble was unavailable. |
| Microsoft Xbox One S Bluetooth revision 2 | Probe published `045E:02FD` with Bluetooth transport and the matching descriptor | LED and application discovery worked, but input did not; rumble was unavailable. |
| Historical Xbox One HID experiment | Retired probe/identity experiments published `045E:02EA` / `045E:02FD` Bluetooth-shaped HID tuples | LED and discovery sometimes worked, but usable input and rumble did not. Historical evidence only; no live product route remains. |

These results apply to this controller, OS, consumer, and OJD build. They show that exact HIDAPI-compatible reports are the working cross-application path for this setup. They do not establish that every application accepts the spoofed identity or that PID and GameController haptics are unavailable for every real controller.

The controller LED reflects the physical GIP session, not a proven haptics backend. It remained on while OJD owned the controller and went off after OJD was quit and the session ended.

In a dedicated SDL `1BAD:F901` run, the installed OJD app logged virtual-device creation but no virtual-output callback. The physical report above therefore does not establish an SDL-to-OJD rumble path; the rare pulse may come from another consumer path and must not be treated as successful rumble. Earlier output-report lines were captured during an Xbox 360 identity run and do not apply to the SDL identity.

OJD now cancels a superseded delayed stop before scheduling a replacement command, so an older accepted request cannot silence a newer rumble request after 250 milliseconds. That scheduling hardening does not make an application emit reports for an identity whose output protocol it does not support. The `sdl2-3` identity and its ASTRO `9886:0024` probe are historical evidence only; OJD now publishes only `hid-xbox-one-s-bt` or `hid-generic`. The input-only GameStop implementation, the redundant `x360-hid` selection, and the two failed Microsoft Bluetooth probe variants were removed from live code; these observations remain as historical evidence.
