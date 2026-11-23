---
name: writing-ojd-controller-records
description: Writes a complete OpenJoystickDriver Controller record for a model with no bundled record, maps its report bits, and replays a capture to test it. Use when ojd does not know a controller.
---

# Writing OJD Controller Records

Goal: describe a model OJD does not know with a `Controller` record, prove it against a capture, and install it.

## Inputs

- `VVVV:PPPP`: the connected model.
- The user, to press controls during the draft and capture.

## Procedure

1. Run `ojd record show VVVV:PPPP`. If it exits 0, a record exists: stop and use `writing-ojd-controller-patches`.
2. Draft the record with one of:
   - `ojd record draft VVVV:PPPP > vvvv-pppp.plist` while the user presses every control for 10 seconds. Save the stderr list of changed bytes and their ranges.
   - `ojd record draft VVVV:PPPP --from-sdl > vvvv-pppp.plist` for a `HIDDescriptor` record from SDL_GameControllerDB.
3. Read [references/input-layouts.md](references/input-layouts.md) before editing `input.layouts`.
4. Run `plutil -convert json -o - vvvv-pppp.plist` and fix each missed or misplaced control. Match each changed byte to the control the user pressed.
5. Run `ojd record validate vvvv-pppp.plist`. Fix the key path it names until it exits 0.
6. Ask the user to hold one known state. Run `ojd --json controller capture VVVV:PPPP --duration 10 > capture.jsonl`.
7. Write `state.json` in the shape of one `ojd --json controller watch VVVV:PPPP` line for that state.
8. Run `ojd record test VVVV:PPPP --packets capture.jsonl --expect state.json`.
   - Exit 0: match. Continue.
   - `E2022`: fix each differing field, then repeat from step 5.
   - `E2011`: the capture or state is invalid, or no report carries input. Redo steps 6 and 7.
9. Run `ojd record install vvvv-pppp.plist --dry-run`, then `ojd record install vvvv-pppp.plist`.
10. Run `ojd controller check VVVV:PPPP` and report each result.

## Family Choice

| Device | `modes[].protocol.family` |
| --- | --- |
| HID descriptor is right | `HIDDescriptor`, optionally with `input.hidUsageMap` |
| HID descriptor is wrong or vendor-defined | `HIDReportLayout` with `input.layouts` |
| speaks a known family | that family; `input.layouts` overrides single controls |

Run `ojd protocol list` for the families. A family OJD lacks (handshake, encryption, transport) needs Swift source; stop and report that.

## Required Keys

- `apiVersion`: `openjoystickdriver/v1alpha3`
- `kind`: `Controller`
- `vendorID`, `productID`: decimal integers
- `modes`: at least one entry with `id` and `protocol.family`
- `input`: `layouts` or `hidUsageMap`
- Optional: `name` (USB product string, verbatim), `tuning`, `server`

## Outputs

- `vvvv-pppp.plist` (lowercase hex), validated, tested, and installed.
- The `record test` result and the `controller check` results.

## Stop Conditions

- Stop if the model has a bundled record; OJD refuses a `Controller` file for it.
- Stop if the record targets raw USB on an Xbox model outside the signed driver list; a record cannot add one.
- Stop and ask before passing `--force`.
- Next steps: `packaging-ojd-mods` to share, `generating-ojd-documents` for many similar models.
