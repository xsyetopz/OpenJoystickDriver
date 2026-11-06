## Context

This change is planning only: it holds specs and tasks, no code.
Sources read for this plan: the code at the paths below; SDL `release-3.4.16` (`SDL_hidapi_steam_triton.c`, `SDL_hidapi_steam.c`, `steam/controller_structs.h`, `steam/controller_constants.h`, `usb_ids.h`); Linux `drivers/hid/hid-steam.c` from `torvalds/linux` master (all read 2026-10-25).
No Steam Controller is in hand for this plan. Hardware-dependent items are gated on the checks in "Hardware Checks (Maintainer)"; testers receive tester builds (`docs/development/tester-builds.md`).

## Research claims checked against the code and the sources

| Claim | Verdict | Evidence |
| --- | --- | --- |
| Triton grip touch (bits 28/29) is dropped. | Confirmed, with sides. | `SteamTritonDriver+Reports.swift:91-101` ends at `0x0800_0000`. SDL: `TRITON_RIGHT_GRIP_TOUCH = 0x10000000` (bit 28), `TRITON_LEFT_GRIP_TOUCH = 0x20000000` (bit 29). The research named the bits without sides. |
| The vocabulary has no grip control. | Confirmed. | `vocabulary.schema.json:45-50` lists `Left/RightStickTouch` and `Left/RightTrackpadTouch` only; `crosswalk.json:627-675` the same. |
| Triton rumble writes only speed fields, so type, intensity and gain are a gap to compare with SDL. | Corrected: parity, not a gap. | SDL `RumbleJoystick` sets `type = 0`, `intensity = 0`, `left.gain = 0`, `right.gain = 0` and writes the speeds; OJD `rumbleReport()` (`SteamTritonDriver.swift:145-152`) writes the same bytes (id, type 0, intensity 0, left speed at 4-5, left gain 6, right speed 7-8, right gain 9). Linux calls its rumble with intensity 0 and gains 2 (left) and 0 (right), so the references differ on the left gain. What gain does is unknown: a hardware experiment (H4), not a fix. |
| Triton pad haptics (`0x81`) are unused. | Confirmed. | `SteamTritonDriver.swift` writes only `0x80`; `ControllerOutputCommand` has no pad haptic case. SDL declares `MsgHapticPulse` (side, on_us, off_us, repeat_count; 8-byte report with the id) but its driver never sends it. Linux sends it on its Ibex path with the left and right pad swapped "for legacy reasons". |
| Triton lacks `CLEAR_DIGITAL_MAPPINGS` and watchdog off, which Linux sends for Ibex. | Confirmed, scoped. | Linux sends both for the Deck and for Ibex: `CLEAR_DIGITAL_MAPPINGS` (id `0x81` as a feature report byte, not the output report `0x81`), then settings `SETTING_LIZARD_MODE = 0` (index 9) and `SETTING_STEAM_WATCHDOG_ENABLE = 0` (index 71, "disable watchdog that tests if Steam is active"). OJD sends setting 9 as its 3 s keep-alive. Linux's Ibex list names `IBEX`, `IBEX_BLE`, `PROTEUS` and `NEREID` devices, which match the Triton family; the numeric IDs were not read, so task 4.1 reads them. SDL omits both. |
| Dongle `1304`/`1305`: OJD's interface choice was not found. | Dropped: already implemented. | `hidConnectionRole` returns `.notARole` for a Triton dongle interface outside 2 to 5 (`ProtocolDriverRegistry+HIDRoles.swift:47-52`), with SDL as its reason. `SteamHIDRoleTests.swift:192-205` covers `0x1304` only; both `1304` and `1305` records use `ValveSteamTriton:Dongle`. Left to do: a `1305` case and a check of the real interface numbers (SDL calls the set "currently" 2 to 5). |
| 2015 USB activation lacks `0x8E` and `SMOOTH_ABSOLUTE_MOUSE = 0`. | Confirmed, wider. | `valve-steam-controller.json` sends `81` then `87` with settings 7 = 7, 8 = 7 (both trackpads `TRACKPAD_NONE`) and 48 = `0x18` (IMU), for USB and, with the `C0` framing, for Bluetooth LE. SDL sends `CLEAR_DIGITAL_MAPPINGS`, `LOAD_DEFAULT_SETTINGS` (`8E 00`), then settings that include `SMOOTH_ABSOLUTE_MOUSE = 0` (index 24, counted from the enumerator list; task 3.1 confirms by reading the pinned file) and `WIRELESS_PACKET_VERSION = 2`. |
| The 2015 Bluetooth LE record is missing. | Corrected. | `28de-1106.json` is `ValveSteamController:BluetoothLE`, and `SteamControllerBluetoothTests` exist. The activation change applies to that transport too. |
| The 2015 deactivation matches SDL's close. | Partly. | OJD sends `85` (default mappings) and `8E`. SDL's `CloseSteamController` sends the same two and then setting 8 (right trackpad mode) = `TRACKPAD_ABSOLUTE_MOUSE` for lizard mouse. Task 3.3 compares them on hardware. |
| Do not follow SteamlessController labels (trackpad settings 7/8 swapped). | Kept. | OJD sets both trackpad modes to the same value, so a swap changes nothing today; settings are named from SDL's enumerator list. |

## Decisions

### D1 Grip touch ids

`LeftGripTouch` and `RightGripTouch`: position-based, UpperCamelCase, like the existing touch ids. Right is bit 28 (`0x1000_0000`), left is bit 29 (`0x2000_0000`).
Every place that lists controls changes in one change, with no alias: the `Control` type, `vocabulary.schema.json`, `Resources/Vocabulary/crosswalk.json` (null mappings, like the other touch ids), `./Scripts/ojd vocabulary regenerate --write`, `Tests/RepositoryScripts/test_control_vocabulary.py`, `VirtualGamepadReportMapping` (touch ids have no SDLCompatible or Generic report slot, like the other touch ids), `ControllerCapabilities`, the presentation name table, the localization bundles (22; reviewed against `LOCALIZATION.md`), the Triton description's `controls.add`, the regenerated records and the equivalence snapshots. Task 2.1 finds every reference with `grep -rn "RightTrackpadTouch\|rightTrackpadTouch"` before editing.

### D2 Pad haptic pulse

A named command `setPadHapticPulse(side, onMicroseconds, offMicroseconds, repeatCount)` and a capability `padHaptic(side)`, advertised by the Triton family only. The report is `81` plus a 7-byte payload (side, on, off, repeat as little-endian 16-bit), 8 bytes in all, sent as a HID output report like the rumble. Side values and the left/right order are not established by SDL; Linux swaps them. Task 5.1 fixes the encoding to H3's capture and does not guess. The first user-facing exposure is a CLI diagnostic under the existing controller output commands; profile and GUI exposure wait for H3.

### D3 2015 activation

Add `8E 00` after `81` and `SMOOTH_ABSOLUTE_MOUSE = 0` (setting 24) to the settings write, for USB and Bluetooth LE, in the description (data). Order follows SDL: clear mappings, load defaults, then settings. Gate: H5 on a USB pad and a dongle pad before the default changes; if a pad misbehaves the datum stays out.

### D4 Triton lizard handling

Adopt `CLEAR_DIGITAL_MAPPINGS` and watchdog off only if H6 shows a benefit (lizard mode stays off without the 3 s resend, or the first seconds of a session have no stray keys). Watchdog off has a cost: if OJD crashes, the firmware no longer restores lizard mode by itself, and the pad stays silent as a keyboard and mouse. If adopted, the deactivation adds `85` (default mappings) and `8E` (as Linux does when it re-enables lizard mode), and a crash test with a tester build proves recovery on replug. Until then SDL's behavior stays.

### D5 Licenses

OJD is licensed under PolyForm Noncommercial 1.0.0 with a commercial license, so GPL code cannot be ported. Linux `hid-steam.c` supplies facts only (byte values, setting indexes, observed sequence); all code is written independently. SDL code (zlib) may be used with its notice kept in `THIRD_PARTY_NOTICES.md`. SteamlessController (MIT) and zydeco (MIT, iOS, private IOKit) are not used.

## Risks

- `LOAD_DEFAULT_SETTINGS` may clear a setting that OJD set earlier in a session (for example, after a reconnect mid-session); the order in D3 puts it before the settings write.
- Watchdog off (D4) can leave a pad in a state without lizard mode after a crash.
- A wrong pad haptic side makes the wrong pad buzz; the capture in H3 prevents a guess.

## Open Questions

- Pad haptic exposure in profiles and the GUI: after H3.
- Whether the dongle interface set is exactly 2 to 5 on the shipped dongles: H7.
