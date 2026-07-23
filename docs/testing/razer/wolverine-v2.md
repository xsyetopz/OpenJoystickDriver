# Test Razer Wolverine V2

This procedure covers [OpenJoystickDriver issue #19](https://github.com/xsyetopz/OpenJoystickDriver/issues/19) for USB device `5426:2601` (`1532:0A29` in hexadecimal).

The bundled record is sourced from Linux xpad and patched with the locally captured interface-0 endpoints `0x81`/`0x01`. It deliberately omits the proposed `shareButton` and `paddles` flags: the report contains no input packet layout that identifies either control, and OJD has no paddle packet decoder. It also omits `set1-before-claim` and a 200 ms post-handshake delay: enumeration reports configuration 1 but does not establish that OJD must select it, and no timing evidence supports the delay. The GIP parser, Xbox One defaults, input mapping, reconnect, LED, and rumble remain unverified. The validation and USB probe sections need no paid Apple Developer Program account, app signing, application-service installation, or DriverKit provisioning; the physical-output section separately requires an installed current app.

## Validate the bundled record

From the repository root:

```bash
./scripts/ojd diagnose record \
  Sources/OpenJoystickDriverKit/Resources/Controllers/1532/1532-0a29.json \
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
  Sources/OpenJoystickDriverKit/Resources/Controllers/1532/1532-0a29.json \
  --seconds 45
```

Confirm the controller remains powered, `RECORD_HANDSHAKE` succeeds, and `USB_RX` packets arrive on the captured endpoint. Test neutral plus press/release for every button, D-pad direction, trigger, stick axis, stick click, and any extra control exposed by the device. Unplug and reconnect the controller, then repeat the handshake and a representative control check. This signing-free probe does not exercise LED or physical output.

If the interface is busy, repeat once with `--detach`, then unplug and reconnect the controller afterward:

```bash
./scripts/ojd diagnose record \
  Sources/OpenJoystickDriverKit/Resources/Controllers/1532/1532-0a29.json \
  --seconds 45 --detach
```

## Check physical output with an installed app

LED and rumble checks require a separately installed current OpenJoystickDriver app. Use the [physical-output procedure](physical-output.md) to generate a device-specific plan:

```bash
OpenJoystickDriver --headless controller output list
OpenJoystickDriver --headless controller output plan 5426 2601
```

Run each generated step individually. Record the player-indicator result and, where the plan exposes them, left and right main rumble plus left and right trigger rumble. This output check is separate from the signing-free record probe and does not establish support by itself.

Attach the probe output and physical-output results to issue #19 with macOS version, Mac model, controller firmware if known, exact OJD commit, whether `--detach` was needed, and results for handshake, every control, reconnect, the indicator, and each exposed actuator. Probe output can contain raw controller packets; inspect and redact it before publication.

The endpoint capture, passing validation, or generating an output plan do not make the record hardware-verified. Keep `verified: false` until accepted physical evidence covers input, reconnect, indicator, and output behavior.
