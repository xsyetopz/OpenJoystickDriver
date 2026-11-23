---
name: adding-ojd-rumble
description: Adds rumble to an OpenJoystickDriver controller with a session.rumble template, including follow-up and stop reports, and checks it with packet captures. Use when a pad's motors stay still.
---

# Adding OJD Rumble

Goal: give a controller's mode a `session.rumble` template that moves its motors, and prove the reports go out.

`HIDReportLayout`, `HIDDescriptor`, and `VendorPS3ThirdParty` modes are input-only until `session.rumble` names a report. OJD sends this report even when macOS handles the pad.

## Inputs

- `CONTROLLER`: the connected pad (`VVVV:PPPP` or an ID).
- A source for the rumble bytes, strongest first:
  1. A Linux driver for the VID:PID (`drivers/hid/hid-*.c`, such as `hid-dr.c`) or SDL's HIDAPI driver.
  2. A USB capture from Windows or Linux while a game rumbles the pad.
  3. The pad's HID descriptor: output report ID and size.
- If no source gives the bytes, stop and ask the user for a capture. Do not guess bytes.

## Procedure

1. Read [references/rumble-template.md](references/rumble-template.md).
2. Hand-test the bytes before writing any file. Show the user the bytes and their source; continue only after the user agrees.
   - Ask the user to run `ojd controller capture CONTROLLER` in a second terminal.
   - Run `ojd controller send CONTROLLER "MOTOR REPORT"`, then one `send` per follow-up report. Each is the whole report in hex. A numbered report starts with its ID; add `--report-id N`. A feature report takes `--feature`.
   - Run `send` again at once with the stop report, or the motor report with zero motor bytes. `send` never stops the motors.
   - DragonRise `0079:0006`: `"51 00 C8 00 C8 00 00"`, `"FA FE 00 00 00 00 00"`, then `"F3 00 00 00 00 00 00"`.
   - Ask the user what they felt. Keep the bytes that moved a motor.
3. Run `ojd record show VVVV:PPPP`. A record exists: write a patch (`writing-ojd-controller-patches`). No record: add the template to the user's record.
4. Fill `session.rumble` in the mode:
   - `report`: `kind`, `id`, `length` from the source.
   - `lowFrequency`: strong, left motor (`--left`). `highFrequency`: weak, right motor (`--right`). Trigger motors: `leftTrigger`, `rightTrigger`.
   - `bytes`: the fixed bytes, such as a command byte.
   - `followUp`: only if the pad needs a commit report after each motor report.
   - `stop`: only if a motor report of zeros does not stop the pad.
   - `resendIntervalMilliseconds`: only if the pad stops on its own after a timeout.
5. Run `ojd record validate FILE`. Fix the key path of each E5007 message and repeat.
6. Run `ojd record install FILE`. Ask the user to reconnect the pad if it was connected.
7. Ask the user to run `ojd controller capture CONTROLLER` in a second terminal.
8. Run `ojd controller rumble CONTROLLER --left 200 --right 200`.
9. Check the capture: one `Tx` motor report, then one `Tx` per `followUp` report, then the `stop` report after the duration (0.45 seconds by default, `--duration` at most 5).
10. Ask the user what they felt. Run `--left 200 --right 0`, then `--left 0 --right 200`, to match each motor to its byte.

## Result Table

| Capture | Felt | Action |
| --- | --- | --- |
| no `Tx` lines | no | the active mode lacks the template, or another app holds the pad; run `ojd controller show` |
| `Tx` as written | no | try another report, length, or kind from the source |
| `Tx` as written | swapped | swap the `lowFrequency` and `highFrequency` bytes |
| `Tx` as written | yes | done; report it with the capture |

## Outputs

- The patch or record with `session.rumble`, validated and installed.
- The capture lines and the user's report of each motor.

## Stop Conditions

- No motor felt on hardware: report the work as hardware-gated. A bundled record gets a template only after a motor is felt.
- Pads under one VID:PID differ inside. Confirm `length` against this pad's descriptor.
- Ask the user before passing `--force`.
