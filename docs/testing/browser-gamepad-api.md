# Browser Gamepad API Manual Evidence

Manual protocol for Plan 06. **ControllerTest.io is the canonical external manual site:** <https://controllertest.io/>.

## Clean-State Protocol

Run every row independently.

1. Record OJD commit/build, macOS version, publication backend, exact browser version, GameSir G7 SE firmware/physical mode, connection path, and selected OJD identity.
1. Stop the prior test and close all Gamepad API pages.
1. Restart OJD for the initial baseline; confirm one physical device and one intended virtual backend in diagnostics.
1. Select exactly one identity and wait for its committed transition result.
1. Open a fresh private browser window or otherwise establish a fresh Gamepad document lifecycle.
1. Open ControllerTest.io and activate the controller as required by browser gesture policy.
1. Use the canonical page to record slot/count, `id`, `mapping`, all buttons, axes, timestamps, connection events, and actuator presence/result.
1. Close the page, stop OJD output, and verify no stale browser entries/callbacks before the next row.
1. Repeat once after a deliberate identity switch. A difference from the clean-start result is classified as identity-transition contamination until lifecycle integrity is established.

Virtual controllers are published only through `IOHIDUserDevice`. Record the macOS version for each run; mark untested macOS versions explicitly unverified and do not infer parity.

## Generic HID Browser Contract

Generic HID publishes the stable OJD identity `1209:4A4F`, allocated by pid.codes, product name `OpenJoystickDriver Generic HID Gamepad`, and a device-neutral, input-only HID Game Pad descriptor. `4F4A:4449` was the earlier layout with a vendor rumble output report; its input layout is unchanged. It does not impersonate a retail controller and does not guarantee Gamepad API `mapping: "standard"`. For this PID, the frozen raw layout is:

- axes 0–3: left X/Y, then right X/Y;
- axes 4–5: LT/RT on the positive half of signed axes, with idle `0`, partial pressure preserved, and full pressure `1` after browser normalization;
- buttons B0–B5 and B8–B17: HID Button usages 1–6 and 9–18;
- no B6/B7 trigger duplicates and no D-pad axis.

An incompatible identity, descriptor, ordering, range, or name change requires a new PID. Raw, lossless trigger axes are accepted even when a test site's standard trigger widgets remain empty. Record non-enumeration as an engine limitation rather than changing OJD to spoof a recognized controller.

Browsers remain unmodified by this work. A future engine contribution should apply the following mapping only after recognizing `1209:4A4F`:

- **Blink:** retain B0–B5/B8–B17, convert the positive halves of axes 4/5 to standard B6/B7, and expose axes 0–3.
- **Gecko:** remap its sequential raw-button array into the same standard button slots, convert the positive halves of axes 4/5 to B6/B7, and expose axes 0–3.
- **WebKit:** recognize the OJD VID/PID, map HID Button usages directly to the standard slots, adapt the positive trigger axes to B6/B7, and expose axes 0–3.

Do not create or submit browser-engine patches as part of OJD's Generic HID fallback work.

## Current Accepted Browser Evidence

Blink's fully correct Apple GameController result is the canonical report-layout oracle. Explicit Apple GameController keeps the Xbox Series `045E:0B13` descriptor, report bytes, button usages, sticks, triggers, hat, Guide, and Share. Automatic now publishes `hid-xbox-one-s-bt` (`045E:02FD`) for every browser and has no browser result yet. The former Gecko Automatic row below published Xbox One S `045E:02E0`, kept the matching axis/trigger order, emitted D-pad through the hat only, and left Share unavailable because Firefox's remapper does not expose B17.

| Browser | Mode | ID/mapping/counts | LT | RT | Issues/reconnect/switch |
| --- | --- | --- | --- | --- | --- |
| Blink | Apple GameController | `045E:0B13`; standard; Xbox Series counts | correct | correct | All controls hardware-verified; report layout frozen |
| Firefox/Gecko | Former Automatic | `045E:02E0`; standard B0–B16 | analog trigger | analog trigger | Hat-only D-pad and Guide; Share unavailable |
| Firefox/Gecko | Explicit Apple GameController | `045E:0B13`; fixed explicit contract | confused with right-stick data | confused with right-stick data | Historical engine mapping failure; explicit profiles do not vary |
| Blink | Generic HID | `4F4A:4449` (former); raw/non-standard; 18 buttons, 6 axes | axis 4 | axis 5 | Retest required on input-only `1209:4A4F` |
| Safari/WebKit | Generic HID | not enumerated | n/a | n/a | Record as WebKit non-enumeration, not an OJD report reorder |

Re-test each row in a fresh document after reconnect and after compatibility switching. Engine classification comes from bundle structure rather than a browser allowlist; unknown or ambiguous fingerprints must use the canonical row.

## Post-Reinstall `0.5.0-beta.4` Observations

User-reported observations after a full development reinstall with a GameSir G7 SE, Chrome 153, macOS 26.6.2, and OJD `0.5.0-beta.4`; the complete clean-state protocol above was not followed:

- Generic HID enumerated with `mapping: n/a`. The left stick occupied axes 0–1, the right stick occupied axes 2–3, LT/RT appeared as binary B6/B7, and no trigger or D-pad axis appeared. The remaining controls occupied B0–B5 and B8–B17. The revised descriptor keeps those sticks and digital controls but moves LT/RT pressure to axes 4–5 and omits B6/B7; this revised layout still requires the clean-state retest below.
- DualShock 4 and DualSense stick Y directions were correct after the report encoding fix.
- Apple GameController and Sony system controls could still be delayed, reserved, or omitted: View was delayed and Guide or Share did not always reach the page. This is controlled by the receiving application's GameController system-gesture policy rather than by OJD's encoded input report. Blink uses [GameController.framework on macOS][1], and applications control gesture delivery through Apple's [`preferredSystemGestureState`][2].

Repeat these observations with the complete protocol before treating them as clean-state verification.

[1]: https://chromium.googlesource.com/chromium/src/%2B/HEAD/device/gamepad/game_controller_data_fetcher_mac.mm
[2]: https://developer.apple.com/documentation/gamecontroller/gccontrollerelement/preferredsystemgesturestate

## Exact `0.5.0-beta.3` Matrix

These nine rows are **user-reported observations**, not verified facts. Repeat each row from clean state, then repeat after a deliberate post-switch identity change. Keep browser name and exact version with each row.

| Row | Engine | Virtual identity | User-reported beta.3 observation | Required manual disposition |
| --- | --- | --- | --- | --- |
| 1 | Blink | Apple GameController | Enumerates as `Xbox Wireless Controller` with `mapping: standard`; Back/View B8 is delayed by the macOS system-gesture recognizer and may require a long press; Guide/Home B16 and Share do not fire | Retain as a Blink limitation unless the browser disables the relevant GameController system gestures and maps the controls; verify native `GCXboxGamepad.buttonShare` and Generic HID separately |
| 2 | Blink | Generic HID | LT Axis5 and RT Axis2 become stuck at -1 after first actuation; expected 0 | Check release to the same valid clean neutral; for raw axes use descriptor-consistent range, for standard mapping use B6/B7 neutral 0 |
| 3 | Blink | X360 HID | Rumble works; no buttons work | Input and claimed output must both work; rumble-only is a failure |
| 4 | Blink | SDL2/3 | Prior X360 identity appears stale; GameSir G7 SE appears as ASTRO C40 TR; no buttons work | Confirm old identity retires and no cross-family physical/virtual relabeling or stale reports remain |
| 5 | Safari/WebKit | SDL2/3 | Not recognized | Reproduce from clean state and record functional recognition or an explicit engine/profile limitation |
| 6 | Safari/WebKit | X360 HID | Recognized and rumble works; no buttons work | Input and claimed output must both work |
| 7 | Safari/WebKit | Generic HID | Not recognized | Record descriptor/engine result or retain an explicit limitation |
| 8 | Safari/WebKit | Apple GameController | Otherwise functional, but four system/stick-click bindings are inverted as in Blink | Check B8/B9/B10/B11 semantics and Guide behavior |
| 9 | Firefox/Gecko | Apple GameController, Generic HID, X360 HID, SDL2/3 | No recognition for all four identities | Run each identity independently; separate OJD, Gecko, permission, and harness causes |

Do not merge rows into a generic browser-support result. Enumeration alone, rumble alone, or a contaminated post-switch result does not verify a row. Label each record **user-reported** until a clean-state manual observation exists; then describe only the observation and exact environment.

The Apple GameController profile can expose Share to native apps as `GCXboxGamepad.buttonShare` while the browser Gamepad API omits it. Treat those as separate consumer results. OJD cannot change a browser's controller-gesture settings or standard-layout mapping.

## Evidence Boundary

Browser engines may enumerate or map the same virtual HID differently. The matrix is closed only by complete control input, relevant release/neutral behavior, reconnect behavior, and actuator observations from the named browser/version and publication backend. No result here establishes universal browser support.
