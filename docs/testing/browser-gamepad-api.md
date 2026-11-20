# Browser Gamepad API Manual Evidence

Web browsers read gamepads through the Gamepad API. This page records how each browser sees OJD's virtual gamepad. The test site for checks by hand is ControllerTest.io (<https://controllertest.io/>).

## Contents

- [Automated Run](#automated-run)
- [Start Clean Each Time](#start-clean-each-time)
- [What Generic HID Promises Browsers](#what-generic-hid-promises-browsers)
- [Accepted Browser Results](#accepted-browser-results)
- [0.5.0-beta.4 Notes After a Reinstall](#050-beta4-notes-after-a-reinstall)
- [0.5.0-beta.3 Table](#050-beta3-table)
- [What Counts as Proof](#what-counts-as-proof)

## Automated Run

`just diagnose-browsers [--as PERSONA] [--browsers firefox,chrome,safari]` opens a logging page in each browser, one after another. In each, it presses every control on one virtual gamepad with `ojd virtual feed`. It prints the standard-mapping slot each browser gave each control (`ok`, `missing`, `differs`) and the rumble result. It writes `results.json` and `events.jsonl` under `.build/browser-gamepad/`. The standard mapping has no slot for Share. A browser engine with 18 buttons and Guide at B16 (Chrome) reports Share as B17, which is where the run expects it.

## Start Clean Each Time

Browsers remember gamepads, so a leftover from the last test can spoil the next one. Run every row on its own.

1. Write down:
   - the OJD commit or build
   - the macOS version and the publishing backend
   - the browser version
   - the GameSir G7 SE firmware, mode, and how it's connected
   - which OJD identity you picked
2. Stop the last test and close every Gamepad API page.
3. Restart OJD. Check in diagnostics that there's one real device and one virtual backend, the one you meant.
4. Pick one identity and wait until OJD reports the switch finished.
5. Open a new private browser window (or otherwise start a fresh Gamepad page).
6. Open ControllerTest.io, and press a button so the browser starts listening (browsers wait for a press).
7. Write down the slot and count, `id`, `mapping`, every button and axis, timestamps, connect and disconnect events, and whether rumble exists and works.
8. Close the page and stop OJD's output. Check that the browser kept no old entries or callbacks.
9. Do it once more after switching identity on purpose. Until the switch is shown to leave nothing behind, treat any difference from the clean start as leftovers from the switch.

OJD makes virtual gamepads only through IOHIDUserDevice. Write down the macOS version for each run; versions nobody tested aren't confirmed.

## What Generic HID Promises Browsers

Generic HID publishes 1209:4A4F (handed out by pid.codes), named `OpenJoystickDriver Generic HID Gamepad`. Its HID Game Pad descriptor belongs to no brand and only sends input. The 4F4A:4449 results further down used the same input layout plus a vendor rumble output report. It doesn't pretend to be any controller you can buy, and it doesn't promise `mapping: "standard"`. The layout for this PID never changes:

- Axes 0 to 3: left X/Y, then right X/Y.
- Axes 4 and 5: LT/RT on the positive half of signed axes. At rest `0`, partly pressed keeps its value, fully pressed is `1` after the browser scales it.
- Buttons B0 to B5 and B8 to B17: HID Button usages 1 to 6 and 9 to 18.
- No B6/B7 copies of the triggers, and no D-pad axis.

Any change that would break this (identity, descriptor, order, range, or name) needs a different PID. Raw trigger axes that lose nothing count as fine, even when a test site's standard trigger pictures stay empty. If a browser doesn't list the gamepad at all, write that down as a browser limit. Don't pose as a controller the browser knows.

OJD doesn't change browsers. A patch to a browser engine should use this mapping only after it recognizes 1209:4A4F:

| Engine | Change |
| --- | --- |
| Blink | Keep B0 to B5 and B8 to B17; turn the positive halves of axes 4/5 into standard B6/B7; show axes 0 to 3 |
| Gecko | Move its numbered raw buttons into the same standard button slots; turn the positive halves of axes 4/5 into B6/B7; show axes 0 to 3 |
| WebKit | Recognize OJD's VID/PID; map HID Button usages straight to the standard slots; turn the positive trigger axes into B6/B7; show axes 0 to 3 |

## Accepted Browser Results

Blink reads the published Xbox Series 045E:0B13 identity correctly. So it's the reference for every report layout: descriptor, report bytes, button usages, sticks, triggers, hat, Guide, Share. OJD's automatic pick publishes SDLCompatible (045E:0B0C) for every browser.

The maintainer tested a Razer Wolverine Tournament Edition (1532:0A15) and a GameSir pad on macOS 27:

| Identity | Safari | Firefox 158.0.1 | Chrome |
| --- | --- | --- | --- |
| SDLCompatible reports on 045E:02FD | Listed as "Xbox Wireless Controller Extended Gamepad", no input (GameController binds that ID, not 0B0C) | Many controls mapped wrongly, no rumble | not recorded |
| Generic | Not listed | Mapped wrongly; right stick at rest at -0.17 on axis 2 | Per contract (triggers on axes 4 and 5, no rumble), except Razer right stick at rest at -0.25 on axis 2 |

GameControllerCompatible publishes the same bit layout as a real 045E:0B13 over Bluetooth, which SDL's HIDAPI driver and Firefox's XboxSeriesXRemapper read. Guide is also on report 2, where GameController reads Home. With `just diagnose-browsers --as game-controller-compatible` on macOS 27:

| Browser | Controls | Rumble |
| --- | --- | --- |
| Firefox 158 | every control in its standard slot but Share | no vibrationActuator |
| Chrome 156 | every control but Guide; Share as B17 | `complete` |
| Safari 27.0.1 | every control but Share | `complete` |

Gecko with the published Xbox One S 045E:02E0 identity kept the same axis and trigger order, and sent the D-pad only through the hat. Share never showed up, because Firefox's remapper doesn't offer B17.

| Browser | Published identity | ID/mapping/counts | LT | RT | Issues/reconnect/switch |
| --- | --- | --- | --- | --- | --- |
| Blink | Xbox Series | 045E:0B13; standard; Xbox Series counts | correct | correct | All controls hardware-verified; report layout frozen |
| Firefox/Gecko | Xbox One S | 045E:02E0; standard B0-B16 | analog trigger | analog trigger | Hat-only D-pad and Guide; Share unavailable |
| Firefox/Gecko | Xbox Series | 045E:0B13; fixed contract | confused with right-stick data | confused with right-stick data | Engine mapping failure |
| Blink | Generic HID with rumble report | 4F4A:4449; raw/non-standard; 18 buttons, 6 axes | axis 4 | axis 5 | Retest required on input-only 1209:4A4F |
| Safari/WebKit | Generic HID | not enumerated | n/a | n/a | Record as WebKit non-enumeration, not an OJD report reorder |

Test each row again in a fresh page after a reconnect and after changing a profile override. OJD tells browser engines apart by how the app bundle is built, not by a list of browser names. An engine it can't identify for sure uses the reference row.

## 0.5.0-beta.4 Notes After a Reinstall

A user reported these after a full development reinstall: GameSir G7 SE, Chrome 153, macOS 26.6.2, OJD 0.5.0-beta.4. They didn't follow the clean-start steps.

- Generic HID showed up with `mapping: n/a`: left stick on axes 0 and 1, right stick on axes 2 and 3, LT/RT as on/off B6/B7, no trigger or D-pad axis, and the other controls on B0 to B5 and B8 to B17. The 1209:4A4F descriptor keeps those sticks and on/off controls, puts LT/RT pressure on axes 4 and 5, and leaves out B6/B7. It needs the clean-start test again.
- The DualShock 4 and DualSense stick Y directions were right.
- Apple GameController and Sony system buttons could arrive late, be kept by macOS, or go missing. View arrived late. Guide or Share didn't always reach the page. The app receiving them decides this through its GameController system-gesture setting, not OJD's report. Blink uses [GameController.framework on macOS][1], and applications control gesture delivery through Apple's [`preferredSystemGestureState`][2].

[1]: https://chromium.googlesource.com/chromium/src/%2B/HEAD/device/gamepad/game_controller_data_fetcher_mac.mm
[2]: https://developer.apple.com/documentation/gamecontroller/gccontrollerelement/preferredsystemgesturestate

## 0.5.0-beta.3 Table

Users reported these nine rows, and nobody has confirmed them. Repeat each one from a clean start, then again after switching identity on purpose. Keep the browser name and version with each row.

| Row | Engine | Virtual identity | User-reported beta.3 observation | Required manual disposition |
| --- | --- | --- | --- | --- |
| 1 | Blink | Apple GameController | Enumerates as `Xbox Wireless Controller` with `mapping: standard`; Back/View B8 is delayed by the macOS system-gesture recognizer and may require a long press; Guide/Home B16 and Share do not fire | Retain as a Blink limitation unless the browser disables the relevant GameController system gestures and maps the controls; verify native GCXboxGamepad.buttonShare and Generic HID separately |
| 2 | Blink | Generic HID | LT Axis5 and RT Axis2 become stuck at -1 after first actuation; expected 0 | Check release to the same valid clean neutral; for raw axes use descriptor-consistent range, for standard mapping use B6/B7 neutral 0 |
| 3 | Blink | X360 HID | Rumble works; no buttons work | Input and claimed output must both work; rumble-only is a failure |
| 4 | Blink | SDL2/3 | Prior X360 identity appears stale; GameSir G7 SE appears as ASTRO C40 TR; no buttons work | Confirm old identity retires and no cross-family physical/virtual relabeling or stale reports remain |
| 5 | Safari/WebKit | SDL2/3 | Not recognized | Reproduce from clean state and record functional recognition or an explicit engine/profile limitation |
| 6 | Safari/WebKit | X360 HID | Recognized and rumble works; no buttons work | Input and claimed output must both work |
| 7 | Safari/WebKit | Generic HID | Not recognized | Record descriptor/engine result or retain an explicit limitation |
| 8 | Safari/WebKit | Apple GameController | Otherwise functional, but four system/stick-click bindings are inverted as in Blink | Check B8/B9/B10/B11 semantics and Guide behavior |
| 9 | Firefox/Gecko | Apple GameController, Generic HID, X360 HID, SDL2/3 | No recognition for all four identities | Run each identity independently; separate OJD, Gecko, permission, and harness causes |

A gamepad that only shows up, only rumbles, or was tested with leftovers from a switch confirms no row. Label records "user-reported" until someone sees it from a clean start.

The Apple GameController profile can give Share to Mac apps as GCXboxGamepad.buttonShare while the browser's Gamepad API leaves it out. Those are separate results. OJD can't change a browser's controller-gesture settings or its standard layout.

## What Counts as Proof

A row is done only when someone saw all of these in the named browser, version, and publishing backend: every control press, every control back at rest, a reconnect, and rumble. No single result proves OJD works in every browser.

## Further Reading

- [Consumer-Binding Evidence](consumer-binding.md)
- [Xbox Fallback Identity Evidence](../development/xbox-identities.md)
