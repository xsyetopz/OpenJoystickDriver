# Test Logitech F310 XInput mapping

This request covers [OpenJoystickDriver issue #11](https://github.com/xsyetopz/OpenJoystickDriver/issues/11) for `046d:c21d` (`1133:49693` decimal).

The current record uses Linux's Xbox 360 packet layout and the hardware-observed
interrupt endpoints `0x81`/`0x02`. OJD's parser maps the XInput button bitfield
to named controls. Confirm the reported semantic labels through Controller
Settings Live or `input state`; the record retains
`verified: false` until the reporter confirms the complete mapping.

No paid Apple Developer Program account, app signing, application service installation, or DriverKit provisioning is required for raw-input verification.

## Validate and capture

Set the F310 switch to **X**, quit Steam and controller utilities, then run:

```bash
./scripts/ojd diagnose record   Sources/OpenJoystickDriverKit/Resources/Controllers/046d/046d-c21d.json   --validate-only

./scripts/ojd diagnose record   Sources/OpenJoystickDriverKit/Resources/Controllers/046d/046d-c21d.json   --seconds 45
```

Press and release one control at a time in this order:

1. A, B, X, Y
2. LB, RB
3. Back, Start, Guide
4. Left-stick click, right-stick click
5. Every D-pad direction
6. Both triggers from rest to fully pressed
7. Both sticks through their full range

Verify that each `USB_RX` packet produces only the matching `EVENT` output. If claiming the interface is busy, repeat once with `--detach` and unplug/reconnect afterward.

## Verify the app and consumers

In Controller Settings, enable Live and confirm LB and RB labels and every active control match the physical input. Use `input watch` if the Settings window is unavailable. Then compare `generic-hid` and `sdl2-3` with the browser diagnostic in Chrome, Firefox, and Safari.

Attach the complete record-probe output, macOS version, Mac model, exact OJD commit, F310 mode-switch position, whether `--detach` was required, Controller Settings Live or CLI input results, and per-browser results to issue #11. Raw packets are included; inspect the output before publishing.

Schema validation and deterministic fixtures do not replace this physical mapping test.
