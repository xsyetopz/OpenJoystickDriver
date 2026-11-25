---
name: diagnosing-ojd-controllers
description: Diagnoses a game controller under OpenJoystickDriver (ojd) on macOS by reading its identity, record, inputs, and packets. Use when a pad is missing, misread, silent, or needs a support report.
license: MPL-2.0
compatibility: Requires macOS with OpenJoystickDriver installed and the ojd command on PATH.
metadata:
  project: OpenJoystickDriver
  apiVersion: openjoystickdriver/v1alpha4
---

# Diagnosing OJD Controllers

Gather evidence about one controller, then pick the smallest fix on the support ladder. Every conclusion rests on command output from this run.

## Name the Controller

`CONTROLLER` is a `VVVV:PPPP` (any case), a session ID (`E-` and 16 characters), or a unit ID (`U-` and 16 characters). A session ID changes on each connection; a unit ID survives reconnects on the same port. When two connected pads share a VID:PID, use an ID.

## Collect Evidence

Run these in order and keep each output:

1. `ojd controller list` lists connected controllers with their IDs and unit IDs.
2. `ojd controller show CONTROLLER` prints the record and its layer, the route, who handles the pad, the mapping source, and whether games see a virtual gamepad.
3. `ojd controller watch CONTROLLER --duration 10` prints the input state while the user presses each control.
4. `ojd controller check CONTROLLER` asks for each declared control in turn and reports `OtherControl` or `Skipped` for a wrong or dead one.
5. `ojd --json controller capture CONTROLLER --duration 10 > capture.jsonl` saves raw packets (`Rx` in, `Tx` out).
6. `ojd diagnose` runs every service check. `--frames 10` measures stutter while the sticks move.
7. `ojd explain CODE` explains any `E` code that appears.

Add `--json` to a command when its output feeds another step.

## Read the Output

| Symptom in `controller show` | Meaning | Next step |
| --- | --- | --- |
| no record, HID gamepad | OJD maps it from the HID descriptor or SDL_GameControllerDB | if a control is wrong, write a record |
| `waits-for-guide-press` | the pad sends nothing until its home button | press the home button |
| `publication.reason` `SystemGamepad` | macOS handles the pad | `ojd controller claim CONTROLLER` makes OJD handle it |
| `no-protocol-match` | no family speaks this device | capture packets, then write a record |
| record from your layer | the user's file changed the model | `ojd record show VVVV:PPPP` lists each field's layer |

A controller that connected before a record changed keeps the older record until it reconnects.

## Choose the Fix

Use the first step that works:

1. Nothing: OJD already binds the pad.
2. A `ControllerPatch` changes a bundled record: see the `writing-ojd-controller-patches` skill.
3. A `Controller` record describes an unknown model: see `writing-ojd-controller-records`.
4. A generator script makes a family of records: see `generating-ojd-documents`.
5. Swift source: only for a handshake, encryption, or transport no document can state.

A fact about one model belongs in a record, never in a Swift branch.

## Report Support Data

Before drafting a bug report or a controller support issue:

- Run every command above that the Mac allows, then ask the user, item by item, for each mode and connection with its VID:PID, the firmware, and captures from Windows or Linux.
- Look up the maker's feature list. Question a "no rumble" or "no lights" that the list contradicts.
- Have the user run each feature (rumble, lights, gyro, speaker) in each mode and connection, with output. Ask again when an answer has no output behind it.
- Refuse to draft the issue while a required field or a listed feature lacks real output. Name each missing item and the command that gets it.
- `ojd diagnose --output support-report.json` writes a support report. Read it with the user before sharing.

## Rules

- Ask before passing `--force` to any `ojd` command.
- Leave serial numbers, unit IDs, Bluetooth addresses, and user paths out of public posts.
