---
name: writing-ojd-controller-records
description: Writes a complete OpenJoystickDriver Controller record for a model with no bundled record, maps its report bits, and replays a capture to test it. Use when ojd does not know a controller.
license: MPL-2.0
compatibility: Requires macOS with OpenJoystickDriver installed and the ojd command on PATH.
metadata:
  project: OpenJoystickDriver
  apiVersion: openjoystickdriver/v1alpha4
---

# Writing OJD Controller Records

A `Controller` record describes a whole model: its family, modes, and input report layout. For a model with a bundled record, write a patch instead (`writing-ojd-controller-patches`).

## Steps

1. Check the model: `ojd record show VVVV:PPPP` exits 1 when no record exists. If one exists, write a patch.
2. Draft:
   - From the pad: `ojd record draft VVVV:PPPP > vvvv-pppp.plist` while the user presses every control for 10 seconds. Stderr lists each report byte that changed, with its lowest and highest value.
   - From SDL_GameControllerDB: `ojd record draft VVVV:PPPP --from-sdl > vvvv-pppp.plist` gives a `HIDDescriptor` record with a `hidUsageMap`.
3. Read the draft as JSON: `plutil -convert json -o - vvvv-pppp.plist`.
4. Fix each control the draft missed or misplaced. Match the changed bytes on stderr to the control the user pressed. Field rules are in [references/input-layouts.md](references/input-layouts.md).
5. Validate: `ojd record validate vvvv-pppp.plist`. It checks that every field lies inside its report. Fix the key path it names.
6. Capture test data: `ojd --json controller capture VVVV:PPPP --duration 10 > capture.jsonl` while the user holds one known state, and `ojd --json controller watch VVVV:PPPP --duration 2` for the matching state line.
7. Write the expected state as `state.json`, in the shape of one `controller watch --json` line.
8. Replay: `ojd record test VVVV:PPPP --packets capture.jsonl --expect state.json`. Exit 0 is a match. `E2022` lists each differing field. `E2011` means the capture or state is invalid or no report carries input.
9. Install: `ojd record install vvvv-pppp.plist --dry-run`, then without `--dry-run`.
10. Confirm with `ojd controller show VVVV:PPPP` and `ojd controller check VVVV:PPPP`.

## Pick the Family

| Device | `modes[].protocol.family` |
| --- | --- |
| HID gamepad whose descriptor is right | `HIDDescriptor` (optionally with `input.hidUsageMap`) |
| HID gamepad whose descriptor is wrong or vendor-defined | `HIDReportLayout` with `input.layouts` |
| a pad that speaks a known family | that family, with `input.layouts` overriding single controls |

`ojd protocol list` lists every family. A family OJD lacks (a handshake, encryption, or new transport) needs Swift source, not a record.

## Record Keys

- `apiVersion` `openjoystickdriver/v1alpha4`, `kind` `Controller`, decimal `vendorID` and `productID`.
- `name`: the USB product string, copied verbatim, optional.
- `modes`: at least one, each with an `id` and `protocol.family`.
- `input`: `layouts` or `hidUsageMap`.
- `tuning`: such as `stickDeadzone`.
- `server`: `OJD` or `System`, only to override who handles the pad.

Name the file `vvvv-pppp.plist` in lowercase hex. To share it, package it (`packaging-ojd-mods`). For many similar models, generate it (`generating-ojd-documents`).

## Rules

- A record states facts about one model. Ground each bit offset in a capture or the HID descriptor.
- A raw-USB record works only when macOS lets OJD open the device. An Xbox model outside the signed driver list cannot be added by record.
- Ask the user before passing `--force`.
