# Test Logitech F310 XInput Mapping

Use this test for [OpenJoystickDriver issue #11][1] and device `046d:c21d` (`1133:49693` decimal).

The current record uses Linux's Xbox 360 packet layout with the hardware-observed interrupt endpoints `0x81`/`0x02`. OJD's parser maps the XInput button bitfield to named controls. Check the reported labels in Controller Settings Live or with (`ojd` is the [command-line tool](../../wiki/Command-Line.md)):

```bash
ojd controller watch 046D:C21D
```

Do not claim support until the reporter confirms the complete mapping.

Record validation is signing-free. Raw-input verification requires a development USBDriverKit build with an exact `046D:C21D` personality; this pair is not in the current production Apple USB entitlement.

[1]: https://github.com/xsyetopz/OpenJoystickDriver/issues/11

## Validate and Capture

Set the F310 switch to X. Quit Steam and any controller utilities, then run:

```bash
./Scripts/ojd diagnose record \
  Sources/OpenJoystickDriverKit/Resources/Controllers/046d/046d-c21d.json --validate-only

./Scripts/ojd diagnose record \
  Sources/OpenJoystickDriverKit/Resources/Controllers/046d/046d-c21d.json --seconds 45
```

Press and release one control at a time in this order:

1. A, B, X, Y
1. LB, RB
1. Back, Start, Guide
1. Left-stick click, right-stick click
1. Every D-pad direction
1. Both triggers from rest to fully pressed
1. Both sticks through their full range

Verify that each `USB_RX` packet produces only the matching `EVENT` output. If the interface is unavailable, capture `./Scripts/ojd diagnose dext`; there is no detach fallback.

## Verify the App and Consumers

Enable Live in Controller Settings. Confirm that LB, RB, and every active control match physical input. Use `controller watch` if the Settings window is unavailable.

Attach these details to issue #11: the complete record-probe output, macOS version, Mac model, exact OJD commit, F310 mode-switch position, DEXT activation state, and Controller Settings Live or CLI state results. Raw packets are included, so inspect the output before publishing.

Schema validation and deterministic fixtures do not replace this physical mapping test.
