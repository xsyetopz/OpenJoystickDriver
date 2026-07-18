# Test Microsoft Xbox One Controller (model 1537)

This procedure covers [OpenJoystickDriver issue #18](https://github.com/xsyetopz/OpenJoystickDriver/issues/18) for USB device `1118:721` (`045E:02D1` in hexadecimal).

The bundled source-backed record selects the GIP Xbox One parser with standard endpoints and the classic default startup sequence. It remains unverified. The validation and USB probe sections need no paid Apple Developer Program account, app signing, application-service installation, or DriverKit provisioning; the physical-output section separately requires an installed current app.

## Validate the bundled record

From the repository root:

```bash
./scripts/ojd diagnose record \
  Sources/OpenJoystickDriverKit/Resources/Controllers/045e/045e-02d1.json \
  --validate-only
```

Expected result:

```text
RECORD_VALIDATION result=valid
```

## Run the signing-free USB probe

Quit Steam, games, and controller utilities. Connect the controller directly by USB, then run:

```bash
./scripts/ojd diagnose record \
  Sources/OpenJoystickDriverKit/Resources/Controllers/045e/045e-02d1.json \
  --seconds 45
```

Confirm the controller remains powered, `RECORD_HANDSHAKE` succeeds, and `USB_RX` packets arrive. Test neutral plus press/release for every button, D-pad direction, trigger, stick axis, and stick click. Unplug and reconnect the controller, then repeat the handshake and a representative control check. This signing-free probe does not exercise LED or physical output.

If the interface is busy, repeat once with `--detach`, then unplug and reconnect the controller afterward:

```bash
./scripts/ojd diagnose record \
  Sources/OpenJoystickDriverKit/Resources/Controllers/045e/045e-02d1.json \
  --seconds 45 --detach
```

## Check physical output with an installed app

LED and rumble checks require a separately installed current OpenJoystickDriver app. Use the [physical-output procedure](physical-output.md) to generate a device-specific plan:

```bash
OpenJoystickDriver --headless physical-output list
OpenJoystickDriver --headless physical-output plan 1118 721
```

Run each generated step individually. Record the player-indicator result and, where the plan exposes them, left and right main rumble plus left and right trigger rumble. This output check is separate from the signing-free record probe and does not establish support by itself.

Attach the probe output and physical-output results to issue #18 with macOS version, Mac model, controller firmware if known, exact OJD commit, whether `--detach` was needed, and results for handshake, every control, reconnect, the indicator, and each exposed actuator. Probe output can contain raw controller packets; inspect and redact it before publication.

Passing validation, receiving a handshake, or generating an output plan does not make the record hardware-verified. Keep `verified: false` until accepted physical evidence covers input, reconnect, indicator, and output behavior.
