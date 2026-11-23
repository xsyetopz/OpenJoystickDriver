---
name: adding-ojd-rumble
description: Adds rumble to an OpenJoystickDriver controller with a session.rumble template, including follow-up and stop reports, and checks it with packet captures. Use when a pad's motors stay still.
argument-hint: "[VVVV:PPPP]"
allowed-tools: Bash(ojd controller show *) Bash(ojd record show *) Bash(ojd record validate *) Bash(plutil *)
license: MPL-2.0
compatibility: Requires macOS with OpenJoystickDriver installed and the ojd command on PATH.
metadata:
  project: OpenJoystickDriver
  apiVersion: openjoystickdriver/v1alpha3
---

# Adding OJD Rumble

Controller: $ARGUMENTS

`HIDReportLayout`, `HIDDescriptor`, and `VendorPS3ThirdParty` modes are input-only until `session.rumble` names a report. OJD sends it even when macOS handles the pad, since macOS never drives these motors.

## Sources

Rumble bytes need a source, never a guess: a vendor report that merely looks right can mean another command to the pad. Strongest first:

1. A Linux driver for the VID:PID (`drivers/hid/hid-*.c`, such as `hid-dr.c`) or SDL's HIDAPI driver.
2. A Windows or Linux USB capture while a game rumbles the pad.
3. The pad's HID descriptor: output report ID and size.

Cite the source of each byte. With no source, stop and ask the user for a capture.

## Template

Keys, limits, E5007 messages, and the DragonRise `0079:0006` worked example: [references/rumble-template.md](references/rumble-template.md).

Mapping decisions:

- `lowFrequency` = strong/left motor (`--left`), `highFrequency` = weak/right (`--right`); trigger motors use `leftTrigger`/`rightTrigger`.
- `bytes` holds fixed bytes such as a command byte; motors overwrite their offsets.
- `followUp` when the pad applies a motor report only after a commit report.
- `stop` when an all-zero motor report does not stop the pad.
- `resendIntervalMilliseconds` only when the pad stops on its own after a timeout.

Bundled model → patch (`/openjoystickdriver:writing-ojd-controller-patches`); unknown model → the user's record.

## Verification

```text
- [ ] ojd record validate FILE
- [ ] ojd record install FILE; reconnect a pad that was already connected
- [ ] second terminal: ojd controller capture CONTROLLER
- [ ] ojd controller rumble CONTROLLER --left 200 --right 200
      expect Tx: motor report, each followUp, then stop after 0.45 s (max --duration 5)
- [ ] user confirms each motor: --left 200 --right 0, then --left 0 --right 200
```

| Capture | Felt | Next |
| --- | --- | --- |
| no `Tx` | no | template missing from the active mode, or another app holds the pad |
| `Tx` as written | no | different report, length, or kind |
| `Tx` as written | swapped | swap the two motor bytes |
| `Tx` as written | yes | works; report with the capture |

A bundled record gains a template only after a motor is felt on hardware. Until then the patch stays in the user's folder or a package, and the work is reported as hardware-gated. Pads under one VID:PID differ inside; confirm `length` against this pad. Ask before `--force`.
