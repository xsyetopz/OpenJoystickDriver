# Browser Gamepad API Manual Evidence

Manual test site: ControllerTest.io (<https://controllertest.io/>).

## Contents

- [Automated Run](#automated-run)
- [Clean-State Protocol](#clean-state-protocol)
- [Generic HID Browser Contract](#generic-hid-browser-contract)
- [Current Accepted Browser Evidence](#current-accepted-browser-evidence)
- [Post-Reinstall 0.5.0-beta.4 Observations](#post-reinstall-050-beta4-observations)
- [Exact 0.5.0-beta.3 Matrix](#exact-050-beta3-matrix)
- [Evidence Boundary](#evidence-boundary)

## Automated Run

`just diagnose-browsers [--as PERSONA] [--browsers firefox,chrome,safari]` opens a logging page in each browser in turn and feeds every control into one virtual gamepad with `ojd virtual feed`. It prints the standard-mapping slot each browser gave each control (`ok`, `missing`, `differs`) and the rumble result, and writes `results.json` and `events.jsonl` under `.build/browser-gamepad/`. The standard mapping has no Share slot; an engine with 18 buttons and Guide at B16 (Chrome) reports Share as B17, where the run expects it.

## Clean-State Protocol

Run every row independently.

1. Record OJD commit/build, macOS version, publication backend, browser version, GameSir G7 SE firmware/physical mode, connection path, selected OJD identity.
2. Stop the previous test; close all Gamepad API pages.
3. Restart OJD. Confirm one physical device and one intended virtual backend in diagnostics.
4. Select one identity; wait for its committed transition result.
5. Open a fresh private browser window (or start a fresh Gamepad document lifecycle).
6. Open ControllerTest.io; activate the controller as the browser gesture policy requires.
7. Record slot/count, `id`, `mapping`, all buttons, axes, timestamps, connection events, actuator presence/result.
8. Close the page; stop OJD output. Check no stale browser entries or callbacks remain.
9. Repeat once after a deliberate identity switch. Classify a difference from the clean-start result as identity-transition contamination until lifecycle integrity holds.

OJD publishes virtual gamepads only through IOHIDUserDevice. Record the macOS version per run; untested versions are unverified.

## Generic HID Browser Contract

Generic HID publishes 1209:4A4F (allocated by pid.codes), product name `OpenJoystickDriver Generic HID Gamepad`, with a device-neutral, input-only HID Game Pad descriptor. The recorded 4F4A:4449 results below used the same input layout plus a vendor rumble output report. It impersonates no retail controller and does not guarantee `mapping: "standard"`. Frozen raw layout for this PID:

- Axes 0-3: left X/Y, then right X/Y.
- Axes 4-5: LT/RT on the positive half of signed axes, idle `0`, partial pressure kept, full pressure `1` after browser normalization.
- Buttons B0-B5 and B8-B17: HID Button usages 1-6 and 9-18.
- No B6/B7 trigger duplicates, no D-pad axis.

A compatibility-breaking change to identity, descriptor, ordering, range, or name needs a different PID. Raw, lossless trigger axes are accepted even when a test site's standard trigger widgets stay empty. Record non-enumeration as an engine limitation; do not spoof a recognized controller.

Browsers are unmodified. An engine contribution should apply this mapping only after recognizing 1209:4A4F:

| Engine | Change |
| --- | --- |
| Blink | Keep B0-B5/B8-B17; convert the positive halves of axes 4/5 to standard B6/B7; expose axes 0-3 |
| Gecko | Remap its sequential raw-button array into the same standard button slots; convert the positive halves of axes 4/5 to B6/B7; expose axes 0-3 |
| WebKit | Recognize the OJD VID/PID; map HID Button usages directly to the standard slots; adapt the positive trigger axes to B6/B7; expose axes 0-3 |

## Current Accepted Browser Evidence

Blink's correct result for the published Xbox Series 045E:0B13 identity is the canonical report-layout oracle: descriptor, report bytes, button usages, sticks, triggers, hat, Guide, Share. Automatic selection publishes SDLCompatible (045E:0B0C) for every browser.

The maintainer tested a Razer Wolverine Tournament Edition (1532:0A15) and a GameSir pad on macOS 27:

| Identity | Safari | Firefox 158.0.1 | Chrome |
| --- | --- | --- | --- |
| SDLCompatible reports on 045E:02FD | Listed as "Xbox Wireless Controller Extended Gamepad", no input (GameController binds that ID, not 0B0C) | Many controls mapped wrongly, no rumble | not recorded |
| Generic | Not listed | Mapped wrongly; right stick at rest at -0.17 on axis 2 | Per contract (triggers on axes 4 and 5, no rumble), except Razer right stick at rest at -0.25 on axis 2 |

GameControllerCompatible publishes the bit layout of a real 045E:0B13 over Bluetooth, read by SDL's HIDAPI driver and Firefox's XboxSeriesXRemapper. Guide is also on report 2, where GameController reads Home. With `just diagnose-browsers --as game-controller-compatible` on macOS 27:

| Browser | Controls | Rumble |
| --- | --- | --- |
| Firefox 158 | every control in its standard slot but Share | no vibrationActuator |
| Chrome 156 | every control but Guide; Share as B17 | `complete` |
| Safari 27.0.1 | every control but Share | `complete` |

Gecko with the published Xbox One S 045E:02E0 identity kept the matching axis/trigger order and emitted the D-pad through the hat only. Share stayed unavailable: Firefox's remapper does not expose B17.

| Browser | Published identity | ID/mapping/counts | LT | RT | Issues/reconnect/switch |
| --- | --- | --- | --- | --- | --- |
| Blink | Xbox Series | 045E:0B13; standard; Xbox Series counts | correct | correct | All controls hardware-verified; report layout frozen |
| Firefox/Gecko | Xbox One S | 045E:02E0; standard B0-B16 | analog trigger | analog trigger | Hat-only D-pad and Guide; Share unavailable |
| Firefox/Gecko | Xbox Series | 045E:0B13; fixed contract | confused with right-stick data | confused with right-stick data | Engine mapping failure |
| Blink | Generic HID with rumble report | 4F4A:4449; raw/non-standard; 18 buttons, 6 axes | axis 4 | axis 5 | Retest required on input-only 1209:4A4F |
| Safari/WebKit | Generic HID | not enumerated | n/a | n/a | Record as WebKit non-enumeration, not an OJD report reorder |

Retest each row in a fresh document after reconnect and after a profile override change. Engine classification uses bundle structure, not a browser allowlist; unknown or ambiguous fingerprints use the canonical row.

## Post-Reinstall 0.5.0-beta.4 Observations

User-reported after a full development reinstall: GameSir G7 SE, Chrome 153, macOS 26.6.2, OJD 0.5.0-beta.4. Clean-state protocol not followed.

- Generic HID enumerated with `mapping: n/a`: left stick on axes 0-1, right stick on axes 2-3, LT/RT as binary B6/B7, no trigger or D-pad axis, remaining controls on B0-B5 and B8-B17. The 1209:4A4F descriptor keeps those sticks and digital controls, puts LT/RT pressure on axes 4-5, and omits B6/B7. Needs the clean-state retest.
- DualShock 4 and DualSense stick Y directions were correct.
- Apple GameController and Sony system controls could be delayed, reserved, or omitted: View was delayed; Guide or Share did not always reach the page. The receiving application's GameController system-gesture policy controls this, not OJD's report. Blink uses [GameController.framework on macOS][1], and applications control gesture delivery through Apple's [`preferredSystemGestureState`][2].

[1]: https://chromium.googlesource.com/chromium/src/%2B/HEAD/device/gamepad/game_controller_data_fetcher_mac.mm
[2]: https://developer.apple.com/documentation/gamecontroller/gccontrollerelement/preferredsystemgesturestate

## Exact 0.5.0-beta.3 Matrix

These nine rows are user-reported, not verified. Repeat each from clean state, then after a deliberate identity switch. Keep browser name and version with each row.

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

Enumeration alone, rumble alone, or a contaminated post-switch result verifies no row. Label records "user-reported" until a clean-state observation exists.

The Apple GameController profile can expose Share to native apps as GCXboxGamepad.buttonShare while the browser Gamepad API omits it: separate results. OJD cannot change a browser's controller-gesture settings or standard-layout mapping.

## Evidence Boundary

Only complete control input, release/neutral, reconnect, and actuator observations from the named browser, version, and publication backend close the matrix. No result establishes universal browser support.

## Further Reading

- [Consumer-Binding Evidence](consumer-binding.md)
- [Xbox Fallback Identity Evidence](../development/xbox-identities.md)
