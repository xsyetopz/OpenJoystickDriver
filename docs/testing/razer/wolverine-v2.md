# Testing the Razer Wolverine V2

This procedure covers [OpenJoystickDriver issue #19](https://github.com/xsyetopz/OpenJoystickDriver/issues/19) for USB device `5426:2601` (`1532:0A29` in hexadecimal).

The bundled record comes from Linux xpad, patched with the locally captured interface-0 endpoints `0x81`/`0x01`. It deliberately omits the proposed `shareButton` and `paddles` flags. The report contains no input packet layout that identifies either control, and OJD has no paddle packet decoder.

The record also omits `set1-before-claim` and a 200 ms post-handshake delay. Enumeration reports configuration 1 but does not establish that OJD must select it, and no timing evidence supports the delay. The GIP parser, Xbox One defaults, input mapping, reconnect, LED, and rumble remain unverified.

Validation is signing-free. This pair is not in the current production Apple USB
entitlement, so the USB facade tries direct IOUSBHost. Use an exact development
DEXT experiment only if live ownership evidence requires it.

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

## Run the raw USB probe

Quit Steam, games, and controller utilities. Connect the controller directly by USB. Then run:

```bash
./scripts/ojd diagnose record \
  Sources/OpenJoystickDriverKit/Resources/Controllers/1532/1532-0a29.json \
  --seconds 45
```

Confirm the controller remains powered, `RECORD_HANDSHAKE` succeeds, and `USB_RX`
packets arrive on the captured endpoint. Test neutral plus press/release for every
button, D-pad direction, trigger, stick axis, stick click, and any extra control
exposed by the device. Unplug and reconnect the controller, then repeat the
handshake and a representative control check.

If the interface is unavailable, preserve the selected route and registry owner;
there is no detach or cross-transport fallback.

## Check physical output with an installed app

LED and rumble checks require a separately installed current OpenJoystickDriver app. Use the [physical-output procedure](physical-output.md) to generate a device-specific plan:

```bash
OpenJoystickDriver --headless controller output list
OpenJoystickDriver --headless controller output plan 5426 2601
```

Run each generated step individually. Record the player-indicator result and,
where the plan exposes them, left and right main rumble plus left and right
trigger rumble. This output check does not establish support by itself.

Attach the probe output and physical-output results to issue #19 with macOS
version, Mac model, controller firmware if known, exact OJD commit, selected USB route,
and results for handshake, every control, reconnect, the indicator, and each
exposed actuator. Probe output can contain raw controller packets; inspect and
redact it before publication.

The endpoint capture, passing validation, or generating an output plan do not make the record hardware-verified. Keep `verified: false` until accepted physical evidence covers input, reconnect, indicator, and output behavior.
