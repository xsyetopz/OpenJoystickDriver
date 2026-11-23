---
name: diagnosing-ojd-controllers
description: Diagnoses a game controller under OpenJoystickDriver (ojd) on macOS by reading its identity, record, inputs, and packets. Use when a pad is missing, misread, silent, or needs a support report.
---

# Diagnosing OJD Controllers

Goal: identify why one controller misbehaves under OpenJoystickDriver and name the smallest fix, using only command output from this session.

## Inputs

- `CONTROLLER`: a `VVVV:PPPP` (any case), a session ID (`E-` + 16 characters), or a unit ID (`U-` + 16 characters).
- If the user gave none, run `ojd controller list` and ask which controller.
- If two connected controllers share a VID:PID, use the ID instead.

## Procedure

1. Run `ojd controller list`. Confirm the controller appears. Record its ID and unit ID.
2. Run `ojd controller show CONTROLLER`. Record: the record and its layer, the route, who handles it, the input mapping source, and the publication state.
3. Tell the user which controls to press, then run `ojd controller watch CONTROLLER --duration 10`.
4. Run `ojd controller check CONTROLLER`. The user presses each control it asks for. `OtherControl` means a wrong bit. `Skipped` means a dead or unmapped control.
5. Run `ojd --json controller capture CONTROLLER --duration 10 > capture.jsonl` while the user presses controls. Keep the file.
6. Run `ojd diagnose`. For stutter, run `ojd diagnose --frames 10` while the user moves the sticks.
7. For each `E` code in any output, run `ojd explain CODE`.
8. Match the findings to the table below and choose the fix.

## Decision Table

| Finding | Cause | Action |
| --- | --- | --- |
| no record, HID gamepad | mapping comes from the HID descriptor or SDL_GameControllerDB | if a control is wrong, use `writing-ojd-controller-records` |
| `waits-for-guide-press` | the pad sends nothing until its home button | ask the user to press it |
| publication reason `SystemGamepad` | macOS handles the pad | run `ojd controller claim CONTROLLER` after the user agrees |
| `no-protocol-match` | no protocol family speaks it | capture packets, then write a record |
| a field from layer `User` | the user's file changed the model | run `ojd record show VVVV:PPPP` |
| wrong value on a bundled model | one detail is wrong | use `writing-ojd-controller-patches` |
| motors never move | no rumble template | use `adding-ojd-rumble` |

A controller connected before a record changed keeps the old record until it reconnects.

Support ladder, smallest first: nothing; a `ControllerPatch`; a `Controller` record; a generator script (`generating-ojd-documents`); Swift source only for a handshake, encryption, or transport no document can state. Put a fact about one model in a record, never in a Swift branch.

## Support Reports

Before drafting a bug report or controller support issue:

1. Run every command in the procedure that the Mac allows.
2. Ask the user, one item at a time, for each mode and connection with its VID:PID, the firmware, and captures from Windows or Linux.
3. Look up the maker's feature list. Question any "no rumble" or "no lights" that the list contradicts.
4. Ask the user to run each feature (rumble, lights, gyro, speaker) in each mode and connection, and paste the output. Ask again when an answer has no output.
5. Run `ojd diagnose --output support-report.json`. Read it with the user before anything is shared.

## Outputs

- A findings list: each claim followed by the command whose output supports it.
- The chosen fix and the next skill to use, or the list of missing evidence.

## Stop Conditions

- Stop and ask before passing `--force` to any `ojd` command.
- Do not draft an issue while a required field or a listed feature lacks real output. Name each missing item and the command that gets it.
- Never put serial numbers, unit IDs, Bluetooth addresses, or user paths in a public post.
