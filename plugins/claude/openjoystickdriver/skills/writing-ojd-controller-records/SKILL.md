---
name: writing-ojd-controller-records
description: Writes a complete OpenJoystickDriver Controller record for a model with no bundled record, maps its report bits, and replays a capture to test it. Use when ojd does not know a controller.
argument-hint: "[VVVV:PPPP]"
allowed-tools: Bash(ojd record show *) Bash(ojd record validate *) Bash(ojd record test *) Bash(ojd record install * --dry-run) Bash(ojd protocol list) Bash(plutil *)
license: MPL-2.0
compatibility: Requires macOS with OpenJoystickDriver installed and the ojd command on PATH.
metadata:
  project: OpenJoystickDriver
  apiVersion: openjoystickdriver/v1alpha4
---

# Writing OJD Controller Records

Model: $ARGUMENTS

A `Controller` record describes a whole model. A bundled model takes a patch instead (`/openjoystickdriver:writing-ojd-controller-patches`); OJD refuses a `Controller` file for it.

## Workflow

```text
- [ ] ojd record show VVVV:PPPP                  exit 1 = no record, continue
- [ ] draft (pick one)
      ojd record draft VVVV:PPPP > vvvv-pppp.plist          user presses every control 10 s
      ojd record draft VVVV:PPPP --from-sdl > vvvv-pppp.plist   HIDDescriptor + hidUsageMap
- [ ] plutil -convert json -o - vvvv-pppp.plist
- [ ] fix missed controls from draft stderr (changed bytes with min/max)
- [ ] ojd record validate vvvv-pppp.plist         fields inside the report
- [ ] ojd --json controller capture VVVV:PPPP --duration 10 > capture.jsonl   user holds one state
- [ ] state.json = one `ojd --json controller watch` line for that state
- [ ] ojd record test VVVV:PPPP --packets capture.jsonl --expect state.json
- [ ] ojd record install vvvv-pppp.plist --dry-run, then without
- [ ] ojd controller check VVVV:PPPP
```

`record test`: exit 0 matches; `E2022` lists differing fields; `E2011` is an invalid capture or state, or no input report.

Bit layout rules (offsets, axes, hats, triggers, touch) and a full example: [references/input-layouts.md](references/input-layouts.md). Read it before editing `input.layouts`.

## Family

| Device | `modes[].protocol.family` |
| --- | --- |
| descriptor right | `HIDDescriptor`, optionally `input.hidUsageMap` |
| descriptor wrong or vendor-defined | `HIDReportLayout` + `input.layouts` |
| speaks a known family | that family; `input.layouts` overrides single controls |

`ojd protocol list` shows families. A missing family (handshake, encryption, transport) needs Swift, not a record.

## Keys

`apiVersion: openjoystickdriver/v1alpha4`, `kind: Controller`, decimal `vendorID`/`productID`, `modes` (each `id` + `protocol.family`), `input`, optional `name` (USB product string verbatim), `tuning`, `server`. File: `vvvv-pppp.plist`, lowercase hex.

Raw-USB records need macOS to let OJD open the device; an Xbox model outside the signed driver list cannot be added by record.

Next: share via `/openjoystickdriver:packaging-ojd-mods`; many similar models via `/openjoystickdriver:generating-ojd-documents`. Ask before `--force`.
