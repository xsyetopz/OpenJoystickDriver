# Browser Gamepad API manual evidence

This page defines the local probe and the manual protocol for Plan 06. **Hardwaretester remains the canonical external manual site:** <https://hardwaretester.com/gamepad>. The local probe supplements it when event, slot, timestamp, raw-array, or actuator detail is needed; it does not replace the canonical site.

## Run the local probe

Serve the directory over localhost. Do not open the file directly from `file://`.

```sh
cd docs/testing/browser-gamepad-probe
python3 -m http.server 8765
```

Open <http://localhost:8765/> in the browser under test. Press **Start capture** explicitly; polling and event capture must not begin before that gesture. Exercise every button, both triggers from idle through full travel and back, both sticks, D-pad, Guide/Home where present, disconnect/reconnect, and haptics when exposed. Press **Stop capture** before switching identity. Use **Copy JSON** or **Download JSON** to retain the redacted observation.

The export contains observed state only: user-entered browser/version and setup fields, capture timestamps, connection events, `getGamepads()` slots/count, `id`, `mapping`, Gamepad timestamp, every button's `value`/`pressed`/`touched`, axes, and exposed haptic actuator fields. It does not collect serials, filesystem paths, a user-agent string, or support/confidence/evidence fields. A JSON observation is not a support claim.

## Clean-state protocol

Run every row independently.

1. Record OJD commit/build, macOS version, publication backend, exact browser version, GameSir G7 SE firmware/physical mode, connection path, and selected OJD identity.
2. Stop the prior test and close all Gamepad API pages.
3. Restart OJD for the initial baseline; confirm one physical device and one intended virtual backend in diagnostics.
4. Select exactly one identity and wait for its committed transition result.
5. Open a fresh private browser window or otherwise establish a fresh Gamepad document lifecycle.
6. Open Hardwaretester and activate the controller as required by browser gesture policy.
7. Use the canonical page and local probe to record slot/count, `id`, `mapping`, all buttons, axes, timestamps, connection events, and actuator presence/result.
8. Close the page, stop OJD output, and verify no stale browser entries/callbacks before the next row.
9. Repeat once after a deliberate identity switch. A difference from the clean-start result is classified as identity-transition contamination until lifecycle integrity is established.

Run the matrix on both publication paths: `IOHIDUserDevice` on macOS 10.15–14 and CoreHID on macOS 15 and later. If a path is not tested, keep it explicitly unverified rather than inferring parity.

## Exact beta.3 matrix

The following nine rows are **user-reported observations**, not verified facts. Repeat each row from clean state, then repeat after a deliberate post-switch identity change. Keep browser name and exact version with each row.

| Row | Engine | Virtual identity | User-reported beta.3 observation | Required manual disposition |
| --- | --- | --- | --- | --- |
| 1 | Chromium | Apple GameController | Enumerates as `Xbox Wireless Controller` with `mapping: standard`; Back/View B8 is delayed by the macOS system-gesture recognizer and may require a long press; Guide/Home B16 does not fire | Retain as a Chromium limitation unless the browser disables the GameController system gesture for its Options/Home elements; verify Generic HID separately for immediate unreserved input |
| 2 | Chromium | Generic HID | LT Axis5 and RT Axis2 become stuck at -1 after first actuation; expected 0 | Check release to the same valid clean neutral; for raw axes use descriptor-consistent range, for standard mapping use B6/B7 neutral 0 |
| 3 | Chromium | X360 HID | Rumble works; no buttons work | Input and claimed output must both work; rumble-only is a failure |
| 4 | Chromium | SDL2/3 | Prior X360 identity appears stale; GameSir G7 SE appears as ASTRO C40 TR; no buttons work | Confirm old identity retires and no cross-family physical/virtual relabeling or stale reports remain |
| 5 | Safari/WebKit | SDL2/3 | Not recognized | Reproduce from clean state and record functional recognition or an explicit engine/profile limitation |
| 6 | Safari/WebKit | X360 HID | Recognized and rumble works; no buttons work | Input and claimed output must both work |
| 7 | Safari/WebKit | Generic HID | Not recognized | Record descriptor/engine result or retain an explicit limitation |
| 8 | Safari/WebKit | Apple GameController | Otherwise functional, but four system/stick-click bindings are inverted as in Chromium | Check B8/B9/B10/B11 semantics and Guide behavior |
| 9 | Firefox/Gecko | Apple GameController, Generic HID, X360 HID, SDL2/3 | No recognition for all four identities | Run each identity independently; separate OJD, Gecko, permission, and harness causes |

Do not merge rows into a generic browser-support result. Enumeration alone, rumble alone, or a contaminated post-switch result does not verify a row. Distinguish the report from the observation: label each record **user-reported** until a clean-state manual observation exists, then describe only what was observed and the exact environment.

## Evidence boundary

The probe is an operational diagnostic, not a protocol authority. Browser engines may enumerate or map the same virtual HID differently. The matrix is closed only by complete control input, relevant release/neutral behavior, reconnect behavior, and actuator observations from the named browser/version and publication backend. No result here establishes universal browser support.
