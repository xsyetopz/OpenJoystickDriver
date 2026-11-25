---
name: diagnosing-ojd-controllers
description: Diagnoses a game controller under OpenJoystickDriver (ojd) on macOS by reading its identity, record, inputs, and packets. Use when a pad is missing, misread, silent, or needs a support report.
argument-hint: "[VVVV:PPPP or controller ID]"
allowed-tools: Bash(ojd controller list *) Bash(ojd controller show *) Bash(ojd record show *) Bash(ojd explain *) Bash(ojd diagnose)
license: MPL-2.0
compatibility: Requires macOS with OpenJoystickDriver installed and the ojd command on PATH.
metadata:
  project: OpenJoystickDriver
  apiVersion: openjoystickdriver/v1alpha4
---

# Diagnosing OJD Controllers

Controller: $ARGUMENTS. When empty, run `ojd controller list` and ask which one.

Build the diagnosis from this run's output only. `CONTROLLER` is a `VVVV:PPPP`, a session ID (`E-…`, changes per connection), or a unit ID (`U-…`, stable per port); use an ID when two pads share a VID:PID.

## Evidence

```text
- [ ] ojd controller show CONTROLLER        record + layer, route, handler, mapping source, publication
- [ ] ojd controller watch CONTROLLER --duration 10   user presses every control
- [ ] ojd controller check CONTROLLER       OtherControl = wrong bit, Skipped = dead control
- [ ] ojd --json controller capture CONTROLLER --duration 10 > capture.jsonl
- [ ] ojd diagnose                          service checks; --frames 10 for stutter
- [ ] ojd explain CODE                      for each E code seen
```

The user operates the pad, so run `watch`, `check`, and `capture` while they press controls, and tell them what to press first.

## Interpretation

| `controller show` says | Cause | Fix |
| --- | --- | --- |
| no record, HID gamepad | mapped from HID descriptor or SDL_GameControllerDB | record, if a control is wrong |
| `waits-for-guide-press` | pad silent until its home button | press it |
| reason `SystemGamepad` | macOS handles the pad | `ojd controller claim CONTROLLER` |
| `no-protocol-match` | no family speaks it | capture, then record |
| layer `User` | the user's file applies | `ojd record show VVVV:PPPP` |

A pad connected before a record changed keeps the old record until it reconnects.

## Fix Ladder

Smallest step that works: nothing → `ControllerPatch` (`/openjoystickdriver:writing-ojd-controller-patches`) → `Controller` record (`/openjoystickdriver:writing-ojd-controller-records`) → generator script (`/openjoystickdriver:generating-ojd-documents`) → Swift source, only for a handshake, encryption, or transport no document can state. A per-model fact is a record field, never a Swift branch.

## Support Reports

Data-mining comes before any bug report or controller support issue:

- Run each command above, then ask item by item for every mode and connection with its VID:PID, the firmware, and Windows or Linux captures.
- Check the maker's feature list yourself. Challenge a "no rumble" or "no lights" it contradicts.
- Each feature (rumble, lights, gyro, speaker) gets a run with output in each mode and connection. "It works" without output gets the command asked again.
- Refuse to draft while a required field or feature lacks output; name each gap and its command.
- `ojd diagnose --output support-report.json` writes a report; read it with the user before sharing.

Ask before any `--force`. Keep serials, unit IDs, Bluetooth addresses, and user paths out of public posts.
