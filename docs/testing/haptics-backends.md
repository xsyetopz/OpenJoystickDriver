# Probe macOS Haptics Backends

Haptics means rumble and other effects you feel in your hands. A game can send rumble down several roads, called backends. Test one road at a time, and write down what the controller physically does before you change the identity OJD shows to games:

```bash
just diagnose-backends --seconds 5
just diagnose-gamecontroller --seconds 5 --rumble
just diagnose-sdl3 --seconds 5 --rumble
just diagnose-rumble-motors 13623 4112
```

| Recipe | Road it tests |
| --- | --- |
| `diagnose-backends` | Lists which backends can see the controller |
| `diagnose-gamecontroller` | Apple's GameController haptics |
| `diagnose-sdl3` | SDL output, the road many games use |
| `diagnose-rumble-motors` | OJD's own rumble command, one motor at a time |

The last line uses the GameSir G7 SE vendor and product IDs in decimal. Use your own, in decimal or `0x` hexadecimal. The script runs `ojd controller rumble` with a `VVVV:PPPP` selector and sends one `sendControllerOutput` command per step. Each rumble has a set length that the app ends; the script waits for that, then sends a stop.

The SDL road can test OJD's own Microsoft Xbox 360 Wired identity (045E:028E). It uses the Xbox 360 HIDAPI descriptor and report format, and OJD publishes it through `IOHIDUserDevice` on every macOS version OJD supports. The probe switches identities with the installed OJD CLI, so it speaks the same service protocol as the running app.

A separate test program tried Apple's old Force Feedback API. OJD has no road through it, so the results below are evidence only. If a HID output report has a size above zero, it might carry raw reports, but that alone proves nothing.

When a game rumbles a virtual gamepad, the real controller gets one command: either a set-rumble with a time limit or a stop-rumble. On a Steam Controller the main motors play on the trackpad haptics. A stop is written once. If a remapping rule is holding the rumble on, that rumble keeps going. Other things a game sends, such as a DualSense lightbar color, don't change anything on the real controller.

The GameController check tests Apple's public controller and haptics road. A gamepad made with `IOHIDUserDevice` gets no public `GCController.haptics` engine.

## GameSir G7 SE Results

September 2, 2026: tested the four physical GIP output channels one at a time with:

```bash
just diagnose-rumble-motors 0x3537 0x1010 200 750
```

Each channel moved exactly one motor:

| Channel | Motor that moved |
| --- | --- |
| `LowFrequency` | Left grip motor |
| `HighFrequency` | Right grip motor |
| `LeftTrigger` | Left trigger motor |
| `RightTrigger` | Right trigger motor |

Each step stopped all four channels before and after its short buzz. This proves OJD's raw-USB GIP output can drive each of the four motors on its own. It doesn't prove every game sends four values.

August 25, 2026, GameSir G7 SE (3537:1010) on OJD's raw USB GIP connection:

| Road | What the software showed | What the controller did |
| --- | --- | --- |
| SDL 1BAD:F901 baseline | The virtual descriptor has an output report, but a PCSX2 run made just for this never called OJD's virtual output. The app only logged that it made the virtual gamepad. The output-report lines in the log came from a separate Xbox 360 identity run | Input works. Normal rumble doesn't: only a rare, faint buzz under a second, with no SDL-to-OJD rumble road. Another program may have caused it. |
| Apple Force Feedback/PID | `FFIsForceFeedback` returned `0x80000003`, and no Force Feedback device opened | No rumble. With OJD closed, macOS showed no controller HID service to test. |
| Apple GameController | `apple-gamecontroller` was picked, but `GCController.controllers()` was empty and there was no public haptics engine | The light stayed on. Input didn't work during the test, so no buzz could be sent. |
| Exact ASTRO SDL HIDAPI Xbox 360 | The `sdl2-3` profile published 9886:0024 with its eight-byte output report | Input and rumble both worked. |
| Microsoft Xbox One S Bluetooth, revision 1 | Probe published 045E:02E0 with a Bluetooth connection and the matching descriptor | Light and app discovery worked. Input didn't, and rumble wasn't available. |
| Microsoft Xbox One S Bluetooth, revision 2 | Probe published 045E:02FD with a Bluetooth connection and the matching descriptor | Light and app discovery worked. Input didn't, and rumble wasn't available. |
| Xbox One HID experiment | Probe and identity tests published 045E:02EA and 045E:02FD HID identities shaped like Bluetooth ones | Light and discovery sometimes worked; usable input and rumble never did. Evidence only; OJD has no road for it. |
| Controller light | Shows the GIP connection to the real controller, not a haptics backend | On while OJD held the controller, off after OJD closed. |

These results hold for this controller, this macOS, these games, and this OJD build. Here, the road that worked across programs was exact HIDAPI-compatible reports. That doesn't prove every program accepts a borrowed identity, or that PID and GameController haptics fail on every real controller.

When a new rumble replaces an old one, OJD cancels the old one's scheduled stop first. So an older request can't cut off a newer rumble after 250 milliseconds. Good timing can't make a program send reports to an identity it doesn't know how to rumble. These were tests, not OJD identities: the `sdl2-3` identity with its ASTRO 9886:0024 probe, the input-only GameStop identity, the `x360-hid` choice, and the two failed Microsoft Bluetooth probes. OJD publishes only `SDLCompatible` or `Generic`.
