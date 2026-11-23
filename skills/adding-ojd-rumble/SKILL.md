---
name: adding-ojd-rumble
description: Adds rumble to an OpenJoystickDriver controller with a session.rumble template, including follow-up and stop reports, and checks it with packet captures. Use when a pad's motors stay still.
license: MPL-2.0
compatibility: Requires macOS with OpenJoystickDriver installed and the ojd command on PATH.
metadata:
  project: OpenJoystickDriver
  apiVersion: openjoystickdriver/v1alpha3
---

# Adding OJD Rumble

A `HIDReportLayout`, `HIDDescriptor`, or `VendorPS3ThirdParty` controller is input-only until one of its modes names a rumble report in `session.rumble`. OJD sends that report even when macOS handles the pad, because macOS does not drive these motors.

## Find the Report

Rumble bytes come from evidence, never a guess. In order of strength:

1. A Linux driver for the VID:PID (`drivers/hid/hid-*.c`, such as `hid-dr.c`), or SDL's HIDAPI driver.
2. A USB capture from Windows or Linux while a game rumbles the pad.
3. The pad's HID report descriptor: its output report ID and size. `ojd controller show CONTROLLER` lists the rumble motors OJD knows.

Note for each fact where it came from. When no source gives the bytes, stop and ask the user for a capture.

## Write the Template

Add `session.rumble` to the mode, in a patch for a bundled model or in the user's own record. Every key and limit is in [references/rumble-template.md](references/rumble-template.md).

- `report`: `kind`, `id`, and `length` from the descriptor or capture.
- One entry per motor with its `byte` offset: `lowFrequency` (strong, left) and `highFrequency` (weak, right), plus `leftTrigger` and `rightTrigger` on pads with trigger motors.
- `bytes`: the fixed bytes of the report, such as a command byte.
- `followUp`: the reports a pad needs after each motor report, such as a commit report.
- `stop`: the report a pad needs to stop, when a motor report with zeros does not.
- `resendIntervalMilliseconds`: only for a pad that stops on its own after a timeout.

## Check It

1. `ojd record validate FILE`. Fix the key path an E5007 message names.
2. `ojd record install FILE`. The running service applies it; reconnect a pad that was already connected.
3. In a second terminal: `ojd controller capture CONTROLLER`.
4. `ojd controller rumble CONTROLLER --left 200 --right 200`. Expect one `Tx` line for the motor report, then one per `followUp` report, then the `stop` report after the duration (0.45 seconds by default, at most 5).
5. Ask the user whether each motor was felt. Run `--left 200 --right 0` and `--left 0 --right 200` to match each motor to its byte.

## Read the Result

| Capture | Felt | Meaning |
| --- | --- | --- |
| no `Tx` lines | no | the mode lacks the template, or another app holds the pad (`ojd controller show`) |
| `Tx` lines as written | no | the pad needs another report, length, or report kind |
| `Tx` lines as written | yes, swapped | swap the `lowFrequency` and `highFrequency` bytes |
| `Tx` lines as written | yes | the template works; report it with the capture |

## Rules

- A bundled record gets a rumble template only after a motor is felt on hardware. Without that, the patch stays in the user's folder or a mod package, and the result is reported as hardware-gated.
- Pads sold under one VID:PID can differ inside. Confirm `length` against this pad's descriptor.
- Ask the user before passing `--force`.
